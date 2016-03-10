package de.hub.emfcompress

import de.hub.emfcompress.Comparer.MyEqualityHelper
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
	var EObject rootOriginal = null
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
	
	static abstract class MyEqualityHelper extends EqualityHelper {
		public abstract def boolean equals(EObject original, EObject revised, boolean isReferenceCompare);
	}
	
	/**
	 * A special EcoreUtils.EqualityHelper. It caches results, it tries to match if comparer
	 * configuration requires it, uses regular equals else. Recursively compares matched
	 * objects.
	 */
	val equalizer = new MyEqualityHelper {
		private def boolean equalsContainment(EObject original, EObject revised) {
			if (get(original) == revised) {
				return true
			}
			
			if (compareWithMatch(original, revised)) {
				val pair = (original as EObject)->(revised as EObject)
				val existingMatch = matches.get(pair)
				if (existingMatch == null) {
					val doMatch = match(original, revised) [o,r|equals(o,r)]						
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

		override equals(EObject original, EObject revised, boolean isContainmentCompare) {
			if (isContainmentCompare) {
				return equalsContainment(original, revised)							
			} else {
				if (get(original) == revised) {
					return true
				}
				
				if (compareWithMatch(original, revised)) {
					val pair = (original as EObject)->(revised as EObject)
					val existingMatch = matches.get(pair)
					if (existingMatch != null) {
						if (!existingMatch) {
							return false
						} else {
							return true
						}
					} 
				}		
								
				if (original.eContainmentFeature == revised.eContainmentFeature) {
					val containmentFeature = original.eContainingFeature
					val originalContainer = original.eContainer
					val revisedContainer = revised.eContainer
					
					if (containmentFeature.many) {
						val originalIndex = (original.eGet(containmentFeature) as List<EObject>).indexOf(original)
						val revisedIndex = (revised.eGet(containmentFeature) as List<EObject>).indexOf(revised)
						if (originalIndex != revisedIndex) {
							return false
						}
					}
					
					if (equals(originalContainer, revisedContainer, false)) {
						return equals(original, revised, true)
					} else {
						return false
					}
				} else {
					return false
				}
			}						
		}
		
		override equals(EObject eObject1, EObject eObject2) {
			return equals(eObject1, eObject2, true)
		}
		
		override protected haveEqualReference(EObject eObject1, EObject eObject2, EReference reference) {
			val value1 = eObject1.eGet(reference);
      		val value2 = eObject2.eGet(reference);

      		if (reference.many) 
          		equals(value1 as List<EObject>, value2 as List<EObject>, reference)
          	else
          		equals(value1 as EObject, value2 as EObject, reference.containment)
		}
		
		private def boolean equals(List<EObject> list1, List<EObject> list2, EReference reference) {
			val size = list1.size();
  			if (size != list2.size()) {
  				false
  			} else {
		      	for (i:0..<size) {
		      		if (!equals(list1.get(i), list2.get(i), reference.containment)) {
		      			return false
		      		}
		      	}
		      	true			      	
		    }			
		}
	}
//	val List<Pair<ReferencedObjectsDelta, List<EObject>>> references = newArrayList
	val List<Pair<EObject,Pair<EObject,EReference>>> referenceSettings = newArrayList
	
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
		referenceSettings.clear
		rootDelta = factory.createObjectDelta
	}
	
	/**
	 * Compares the given elements and produces a delta that can be used to
	 * patch the first object (original) to yield the second object (revised).
	 */
	public def ObjectDelta compare(EObject original, EObject revised) {
		reset
		
		rootOriginal = original
		rootDelta.originalClass = original.eClass
		// First we recursively compare all settings of the given objects.
		// This might create deltas with references. 		
		equalizer.equals(original, revised, true)
		// References to elements of the original model (created in the previous step)
		// have been and are now added/replaced as/with ObjectDeltas and corresponding
		// proxies.
		handleReferences
	
		return rootDelta		
	}
	
	val Map<EObject,EObject> matches2 = newHashMap
	
	public def boolean match(EObject original, EObject revised) {
		if (original.eClass != revised.eClass) {
			return false	
		}
		
		return if (match(original, revised) [o,r|match(o,r)]) {
			matches2.put(original,revised)
			val eClass = original.eClass
			val matchReferences = eClass.EAllReferences.filter[
				containment && compareWithMatch(eClass, it)
			]
			for (matchReference:matchReferences) {
				val List<EObject> originalValues = original.eGetList(matchReference)
				val List<EObject> revisedValues = revised.eGetList(matchReference)
				val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
					match(comparedOriginal,comparedRevised) 
				]
				patch.deltas.forEach[
					val replacedObjectValues = factory.createContainedObjectsDelta
					it.revised.lines.forEach[
						replacedObjectValues.revisedObjectContainments += it.containment																		
					]
					replacedObjectValues.originalStart = it.original.position
					replacedObjectValues.originalEnd = it.original.position + it.original.size
					original.settingDelta(matchReference).valueDeltas += replacedObjectValues								
				]				
			}	
			true	
		} else {
			false
		}
	}
	
	private def <T> List<T> eGetList(EObject container, EStructuralFeature feature) {
		return if (feature.many) {
			container.eGet(feature) as List<T>
		} else {
			#[container.eGet(feature) as T]	
		}
	}
	
	private def void handleReferences() {
		// handle references in references
		val List<Pair<ReferencedObjectsDelta, List<EObject>>> references = newArrayList
		for(refernceSetting:referenceSettings) {
			val original = refernceSetting.key
			val revised = refernceSetting.value.key
			val feature = refernceSetting.value.value
			
			val List<ValuesDelta> valueDeltas = newArrayList
			if (feature.many) {
				val originalValues = original.eGet(feature) as List<EObject>
					val revisedValues = revised.eGet(feature) as List<EObject>
					val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
						compareValues(comparedOriginal, comparedRevised,feature) 
					]
					if (!patch.deltas.empty) {
						patch.deltas.forEach[
							val replacedObjectValues = factory.createReferencedObjectsDelta
							replacedObjectValues.originalStart = it.original.position
							replacedObjectValues.originalEnd = it.original.position + it.original.size
							val referencedValues = newArrayList
							it.revised.lines.forEach[
								referencedValues.add(it as EObject)
							]
							references.add(replacedObjectValues->referencedValues)
							
							valueDeltas += replacedObjectValues
						]					
					}
			} else {
				val originalValue = original.eGet(feature) as EObject
				val revisedValue = revised.eGet(feature) as EObject
				if (!compareValues(originalValue, revisedValue, feature)) {
					val replacedObjectValues = factory.createReferencedObjectsDelta
					if (revisedValue != null) {
						val referencedValues = newArrayList(revisedValue as EObject)									
						references.add(replacedObjectValues->referencedValues)									
					}
					valueDeltas += replacedObjectValues
				}
			}
			if (!valueDeltas.empty) {
				val settingDelta = original.settingDelta(feature)					
				settingDelta.valueDeltas += valueDeltas
			}
		}
		
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
		if (original == rootOriginal) {
			return rootDelta
		}
		
		val container = original.eContainer
		
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
		return derivedFromOpposite(feature, true)
	}
	
	private def boolean derivedFromOpposite(EStructuralFeature feature, boolean check) {
		switch(feature) {
			EAttribute: return false
			EReference: 
				if (feature.containment) {
					return false
				} else {
					return if (feature.EOpposite != null) {
						val opposite = feature.EOpposite
						val result = if (!opposite.changeable || opposite.derived) {
							false
						} else if (opposite.containment) {
							true
						} else if (!feature.many && opposite.many) {
							false // prefer the single valued feature
						} else if (feature.many && !opposite.many) {
							true
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
						
						if (check) {
							precondition[result != derivedFromOpposite(opposite, false)]
						}
						
						return result		
					} else {
						false
					}					
				}
			default: return unreachable as Boolean
		}		
	}
	
	private def containment(EObject revisedObject) {
		val matchingOriginalObject = equalizer.get(revisedObject)
		return if (matchingOriginalObject == null) {
			val revisedContainment = factory.createRevisedObjectContainment
			revisedContainment.revisedObject = copier.copy(revisedObject)
			revisedContainment
		} else {
			val originalContainment = factory.createOriginalObjectContainment
			originalContainment.originalObject = matchingOriginalObject.objectDelta
			precondition[originalContainment.originalObject != null]
			originalContainment
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
						patch.deltas.forEach[
							val replacedValues = switch feature {
								EAttribute: {
									val replacedDataValues = factory.createDataValuesDelta
									it.revised.lines.forEach[replacedDataValues.revisedValues += it]
									replacedDataValues							
								}
								EReference: {
									if (feature.containment) {
										val replacedObjectValues = factory.createContainedObjectsDelta
										it.revised.lines.forEach[
											replacedObjectValues.revisedObjectContainments += (it as EObject).containment
										]
										replacedObjectValues									
									} else {
										referenceSettings += original -> (revised -> feature)
										null
//										val replacedObjectValues = factory.createReferencedObjectsDelta
//										val referencedValues = newArrayList
//										it.revised.lines.forEach[
//											referencedValues.add(it as EObject)
//										]
//										references.add(replacedObjectValues->referencedValues)
//										replacedObjectValues
									}
								}
								default: unreachable as ValuesDelta
							}
							if (replacedValues != null) {
								replacedValues.originalStart = it.original.position
								replacedValues.originalEnd = it.original.position + it.original.size
								valueDeltas += replacedValues								
							}
						]				
					}
				} else {
					val revisedValue = revised.eGet(feature)
					if (!compareValues(original.eGet(feature), revisedValue, feature)) {
						switch feature {
							EAttribute: {
								val replacedDataValues = factory.createDataValuesDelta
								if (revisedValue != null) {
									replacedDataValues.revisedValues += revisedValue
								}
								valueDeltas += replacedDataValues
							}
							EReference: {
								if (feature.containment) {
									val replacedObjectValues = factory.createContainedObjectsDelta
									if (revisedValue != null) {										
										replacedObjectValues.revisedObjectContainments += (revisedValue as EObject).containment
									}
									valueDeltas += replacedObjectValues
								} else {
									referenceSettings += original -> (revised -> feature)
//									val replacedObjectValues = factory.createReferencedObjectsDelta
//									if (revisedValue != null) {
//										val referencedValues = newArrayList(revisedValue as EObject)									
//										references.add(replacedObjectValues->referencedValues)									
//									}
//									replacedObjectValues
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
						return equalizer.equals(original as EObject, revised as EObject, feature.containment)
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
