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

class Comparer {
	
	val factory = EmfCompressFactory.eINSTANCE
	
	val DObject rootDelta = factory.createDObject
	val Map<EObject,DObject> objectDeltas = newHashMap
	val Map<Pair<EObject,EStructuralFeature>, DSetting> settingDeltas = newHashMap	
	
	val Map<Pair<EObject,EObject>, Boolean> matches = newHashMap	
	val copier = new Copier {		
		override get(Object key) {
			val result = super.get(key)
			if (result == null) {
				// a reference is requested that was not copied
				precondition[key instanceof EObject]
				val revised = key as EObject
				val original = equalizer.get(revised)
				precondition[original != null]
				val delta = original.delta
				var proxy = delta.proxy
				if (proxy == null) {
					val proxyClass = getTarget(revised.eClass)
					proxy = proxyClass.EPackage.EFactoryInstance.create(proxyClass)
					delta.proxy = proxy
				}	
				put(revised,proxy)			
				return proxy				
			} else {
				return result
			}
		}		
	}
	val equalizer = new EqualityHelper {		
		override equals(EObject original, EObject revised) {
			if (couldMatch(original, revised)) {
				val pair = (original as EObject)->(revised as EObject)
				val existingMatch = matches.get(pair)
				if (existingMatch == null) {
					val doMatch = doMatch(revised, original)						
					matches.put(pair, doMatch)
					if (doMatch) {
						put(original, revised)
						put(revised, original)
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
	val List<Pair<DReferencedObjectValues, List<EObject>>> references = newArrayList
	
	public static def DObject compare(EObject original, EObject revised) {
		val comparer = new Comparer()
		comparer.rootDelta.originalClass = original.eClass
		comparer.compareContainment(original, revised)
		comparer.handleReferences
	
		return comparer.rootDelta		
	}
	
	private def void handleReferences() {
		// handle references in references
		for(referenceDelta:references) {
			val delta = referenceDelta.key
			val values = referenceDelta.value
			for(value:values) {
				val copy = copier.get(value)
				val reference = if (copy != null) {
					val newReference = factory.createDRevisedObjectReference
					newReference.value = copy
					newReference
				} else {
					val equalOriginal = equalizer.get(value)
					if (equalOriginal != null) {
						val newReference = factory.createDOriginalObjectReference
						newReference.value = equalOriginal.delta
						newReference
					} else {
						unreachable as DObjectReference
					}
				}
				delta.references.add(reference)
			}
		}
		
		// handle references in copier, the copier's specialized get method will create proxies for non copied elements
		copier.copyReferences	
	}
	
	private def DSetting delta(EObject container, EStructuralFeature feature) {
		val pair = container->feature
		val existing = settingDeltas.get(pair) 
		if (existing == null) {
			val containerDelta = container.delta
			val featureID = container.eClass.getFeatureID(feature)			
			val newSettingDelta = factory.createDSetting
			newSettingDelta.featureID = featureID
			containerDelta.settings.add(newSettingDelta)
			settingDeltas.put(pair, newSettingDelta)
			return newSettingDelta
		} else {
			return existing
		}		
	}
	
	private def DObject delta(EObject original) {
		val container = original.eContainer
		if (container == null) {
			return rootDelta
		}
		
		val existingDelta = objectDeltas.get(original) 
		if (existingDelta == null) {			
			val newDelta = factory.createDObject
			newDelta.originalClass = original.eClass
			objectDeltas.put(original, newDelta)
			
			val containmentFeature = original.eContainmentFeature
			if (containmentFeature.many) {
				newDelta.originalIndex = (container.eGet(original.eContainmentFeature) as List<Object>).indexOf(original)			
			}
			container.delta(containmentFeature).matches.add(newDelta)
			
			return newDelta
		} else {
			return existingDelta
		}
	}
	
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
	
	private def void compareContainment(EObject original, EObject revised) {
		precondition[original.eClass == revised.eClass]
		
		val eClass = original.eClass	
		for(feature:eClass.EAllStructuralFeatures) {
			if (feature.changeable && !feature.derived && !feature.derivedFromOpposite) {
				val List<DValues> valueDeltas = newArrayList		 				
				if (feature.many) {
					val originalValues = original.eGet(feature) as List<Object>
					val revisedValues = revised.eGet(feature) as List<Object>
					val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
						compare(comparedOriginal,comparedRevised,feature) 
					]
					if (!patch.deltas.empty) {
						valueDeltas += patch.deltas.map[
							val replacedValues = switch feature {
								EAttribute: {
									val replacedDataValues = factory.createDDataValues
									it.revised.lines.forEach[replacedDataValues.values += it]
									replacedDataValues							
								}
								EReference: {
									if (feature.containment) {
										val replacedObjectValues = factory.createDContainedObjectValues
										it.revised.lines.forEach[replacedObjectValues.values += copier.copy(it as EObject)]
										replacedObjectValues									
									} else {
										val replacedObjectValues = factory.createDReferencedObjectValues
										val referencedValues = newArrayList
										it.revised.lines.forEach[referencedValues.add(it as EObject)]
										references.add(replacedObjectValues->referencedValues)
										replacedObjectValues
									}
								}
								default: unreachable as DValues
							}
							replacedValues.start = it.original.position
							replacedValues.end = it.original.position + it.original.size
							return replacedValues
						]				
					}
				} else {
					compare(original.eGet(feature), revised.eGet(feature), feature)
				}
				
				if (!valueDeltas.empty) {
					val settingDelta = original.delta(feature)					
					settingDelta.deltas += valueDeltas
				}
			}
		}		
	}
	
	protected def boolean couldMatch(EObject original,EObject revised) {
		return original.eClass == revised.eClass && original.eClass.getEStructuralFeature("name") != null
	}
	
	protected def boolean doMatch(EObject original,EObject revised) {
		val nameFeature = original.eClass.getEStructuralFeature("name")
		return original.eGet(nameFeature) == revised.eGet(nameFeature)
	} 
	
	private def boolean compare(Object original, Object revised, EStructuralFeature feature) {
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
