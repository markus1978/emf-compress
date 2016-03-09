package de.hub.emfcompress

import difflib.DiffUtils
import java.util.List
import java.util.Map
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil.Copier
import org.eclipse.emf.ecore.util.EcoreUtil.EqualityHelper

/**
 * A comparer can be used to compare to objects (and everything they contain). The comparison produces a 
 * delta that can be used to patch one object (original) to yield the other object (revised).
 * The patches in fully independent of the original and revised and holds no direct EMF references
 * to either of the models. Elements of the original model are referred to by means of features and indices;
 * elements to the revised model are copied to be part of the patch.
 * 
 * Comparer can be configured through the protected callback methods.
 */
class Comparer {
	
	val EmfCompressFactory factory
	val extension ComparerConfiguration config 
	
	var ObjectDelta rootDelta = null
	val Map<EObject,ObjectDelta> objectDeltas = newHashMap
	val Map<Pair<EObject,EStructuralFeature>, SettingDelta> settingDeltas = newHashMap	
	val Map<Pair<EObject,EObject>, Boolean> matches = newHashMap
	
	/**
	 * A special EcoreUtils.Copier that deals with references that have targets outside 
	 * the copied object's containment hierarchies.
	 */	
	val copier = new Copier {
		/**
		 * A specialization of the inherited get method. It provides proxys for referenced
		 * objects that are outside the containment hierarchies of copied elements.
		 */
		override get(Object key) {
			val result = super.get(key)
			if (result == null) {
				// a reference is requested that was not copied
				precondition[key instanceof EObject]
				val revised = key as EObject
				val original = equalizer.get(revised)
				precondition[original != null]
				val delta = original.objectDelta
				var proxy = delta.originalProxy
				if (proxy == null) {
					val proxyClass = getTarget(revised.eClass)
					proxy = proxyClass.EPackage.EFactoryInstance.create(proxyClass)
					delta.originalProxy = proxy
				}		
				return proxy				
			} else {
				return result
			}
		}		
	}
	/**
	 * A special EcoreUtils.EqualityHelper. It caches results, it tries to match if comparer
	 * configuration requires it, uses regular equals else. Recursively compares matched
	 * objects.
	 */
	val equalizer = new EqualityHelper {		
		override equals(EObject original, EObject revised) {
			if (compareWithMatch(original, revised)) {
				val pair = (original as EObject)->(revised as EObject)
				val existingMatch = matches.get(pair)
				if (existingMatch == null) {
					val doMatch = match(revised, original)						
					matches.put(pair, doMatch)
					if (doMatch) {
						put(original, revised)
						put(revised, original)
						compareSettings(original, revised)
					}			
					doMatch														
				} else {						
					existingMatch
				}
			} else {
				super.equals(original, revised)
			}						
		}
	}
	val List<Pair<ReferencedObjectsDelta, List<EObject>>> references = newArrayList
	
	new(ComparerConfiguration config, EmfCompressFactory factory) {
		this.factory = factory
		this.config = config
	}
	
	new(ComparerConfiguration config) {
		this.factory = EmfCompressFactory.eINSTANCE
		this.config = config
	}
	
	private def void reset() {
		equalizer.clear
		copier.clear
		objectDeltas.clear
		settingDeltas.clear
		matches.clear
		references.clear
		rootDelta = factory.createObjectDelta
	}
	
	/**
	 * Compares the given elements and produces a delta that can be used to
	 * patch the first object (original) to yield the second object (revised).
	 */
	public def ObjectDelta compare(EObject original, EObject revised) {
		reset
		
		rootDelta.originalClass = original.eClass
		// First we recursively compare all settings of the given objects.
		// This might create deltas with references. 		
		compareSettings(original, revised)
		// References to elements of the original model (created in the previous step)
		// have been and are now added/replaced as/with ObjectDeltas and corresponding
		// proxies.
		handleReferences
	
		return rootDelta		
	}
	
	private def void handleReferences() {
		// handle references in references
		for(referenceDelta:references) {
			val delta = referenceDelta.key
			val values = referenceDelta.value
			for(value:values) {
				val copy = copier.get(value)
				val reference = if (copy != null) {
					val newReference = factory.createRevisedObjectReference
					newReference.revisedObject = copy
					newReference
				} else {
					val equalOriginal = equalizer.get(value)
					if (equalOriginal != null) {
						val newReference = factory.createOriginalObjectReference
						newReference.originalObject = equalOriginal.objectDelta
						newReference
					} else {
						unreachable as ObjectReference
					}
				}
				delta.revisedObjectReferences.add(reference)
			}
		}
		
		// handle references in copier, the copier's specialized get 
		// method will create proxies for non copied elements
		copier.copyReferences	
	}
	
	/**
	 * Transforms a given original and feature into a SettingDelta, if it
	 * does not already exist. Used for lazy delta construction.	  
	 */
	private def SettingDelta settingDelta(EObject original, EStructuralFeature feature) {
		val pair = original->feature
		val existing = settingDeltas.get(pair) 
		if (existing == null) {
			val containerDelta = original.objectDelta
			val featureID = original.eClass.getFeatureID(feature)			
			val newSettingDelta = factory.createSettingDelta
			newSettingDelta.featureID = featureID
			containerDelta.settingDeltas.add(newSettingDelta)
			settingDeltas.put(pair, newSettingDelta)
			return newSettingDelta
		} else {
			return existing
		}		
	}
	
	/**
	 * Transforms a given original into a ObjectDelta, if it
	 * does not already exist. Used for lazy delta construction.	  
	 */
	private def ObjectDelta objectDelta(EObject original) {
		val container = original.eContainer
		if (container == null) {
			return rootDelta
		}
		
		val existingDelta = objectDeltas.get(original) 
		if (existingDelta == null) {			
			val newDelta = factory.createObjectDelta
			newDelta.originalClass = original.eClass
			objectDeltas.put(original, newDelta)
			
			val containmentFeature = original.eContainmentFeature
			if (containmentFeature.many) {
				newDelta.originalIndex = (container.eGet(original.eContainmentFeature) as List<Object>).indexOf(original)			
			}
			container.settingDelta(containmentFeature).matchedObjects.add(newDelta)
			
			return newDelta
		} else {
			return existingDelta
		}
	}
	
	/**
	 * For a pair of opposing references, only one should be used during comparison.
	 * @returns true, if the given feature is already used during comparison.
	 */
	private def boolean derivedFromOpposite(EStructuralFeature feature) {
		switch(feature) {
			EAttribute: false
			EReference: 
				if (feature.EOpposite != null) {
					val opposite = feature.EOpposite
					if (!opposite.changeable || opposite.derived) {
						false
					} else if (opposite.containment) {
						true
					} else if (!feature.many && opposite.many) {
						false // prefer the single valued feature
					} else {
						// use a unique but meaningless criteria
						val featureHC = System.identityHashCode(feature)
						val oppositeHC = System.identityHashCode(opposite)
						if (featureHC == oppositeHC) { // extremely unlikely 
							unreachable as Boolean // TODO compare by qualified name
						} else {
							featureHC > oppositeHC
						}
					}
				} else {
					false
				}
			default: unreachable as Boolean
		}
	}
	
	/**
	 * Compares the settings of the given objects. It lazily creates object deltas for the given original
	 * and adds all found setting deltas to this original. Method is indirectly recursive as long as two
	 * objects have not been compared already.
	 */
	private def void compareSettings(EObject original, EObject revised) {
		precondition[original.eClass == revised.eClass]
		
		val eClass = original.eClass	
		for(feature:eClass.EAllStructuralFeatures) {
			if (feature.changeable && !feature.derived && !feature.derivedFromOpposite && !feature.ignore) {
				val List<ValuesDelta> valueDeltas = newArrayList		 				
				if (feature.many) {
					val originalValues = original.eGet(feature) as List<Object>
					val revisedValues = revised.eGet(feature) as List<Object>
					val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
						compareValues(comparedOriginal,comparedRevised,feature) 
					]
					if (!patch.deltas.empty) {
						valueDeltas += patch.deltas.map[
							val replacedValues = switch feature {
								EAttribute: {
									val replacedDataValues = factory.createDataValuesDelta
									it.revised.lines.forEach[replacedDataValues.revisedValues += it]
									replacedDataValues							
								}
								EReference: {
									if (feature.containment) {
										val replacedObjectValues = factory.createContainedObjectsDelta
										it.revised.lines.forEach[replacedObjectValues.revisedObjects += copier.copy(it as EObject)]
										replacedObjectValues									
									} else {
										val replacedObjectValues = factory.createReferencedObjectsDelta
										val referencedValues = newArrayList
										it.revised.lines.forEach[
											referencedValues.add(it as EObject)
										]
										references.add(replacedObjectValues->referencedValues)
										replacedObjectValues
									}
								}
								default: unreachable as ValuesDelta
							}
							replacedValues.originalStart = it.original.position
							replacedValues.originalEnd = it.original.position + it.original.size
							return replacedValues
						]				
					}
				} else {
					val revisedValue = revised.eGet(feature)
					if (!compareValues(original.eGet(feature), revisedValue, feature)) {
						valueDeltas += switch feature {
							EAttribute: {
								val replacedDataValues = factory.createDataValuesDelta
								if (revisedValue != null) {
									replacedDataValues.revisedValues += revisedValue
								}
								replacedDataValues
							}
							EReference: {
								if (feature.containment) {
									val replacedObjectValues = factory.createContainedObjectsDelta
									if (revisedValue != null) {
										replacedObjectValues.revisedObjects += copier.copy(revisedValue as EObject)
									}
									replacedObjectValues
								} else {
									val replacedObjectValues = factory.createReferencedObjectsDelta
									if (revisedValue != null) {
										val referencedValues = newArrayList(revisedValue as EObject)									
										references.add(replacedObjectValues->referencedValues)									
									}
									replacedObjectValues
								}
							}
							default: unreachable as ValuesDelta
						}
					}
				}
				
				if (!valueDeltas.empty) {
					val settingDelta = original.settingDelta(feature)					
					settingDelta.valueDeltas += valueDeltas
				}
			}
		}		
	}
	
	/**
	 * Compares the given object values (that belong to the given feature). 
	 * @returns true, if the values are equal or match.
	 */
	private def boolean compareValues(Object original, Object revised, EStructuralFeature feature) {
		return if (original == null || revised == null) {
			original == revised
		} else if (original == revised) {
			true
		} else {	
			switch feature {
				EAttribute: {
					if (original.equals(revised)) {
						true
					} else {
						false
					}	
				}
				EReference: {
					if (equalizer.get(original) != revised) {
						return equalizer.equals(original as EObject, revised as EObject)
					} else {
						true
					}					
				}
				default: unreachable as Boolean
			}			
		}
	}
	
	private def Object unreachable() {
		throw new RuntimeException("Unreachable")
	}
	
	private def precondition(()=>boolean condition) {
		if (!condition.apply) {
			throw new RuntimeException("Condition failed")
		}
	}
}
