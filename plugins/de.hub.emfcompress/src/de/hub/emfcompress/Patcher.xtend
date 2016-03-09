package de.hub.emfcompress

import com.google.common.collect.AbstractIterator
import java.util.Collection
import java.util.Iterator
import java.util.List
import java.util.Map
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil
import org.eclipse.emf.ecore.util.EcoreUtil.Copier

/**
 * A Patcher can be used to patch a given original with a delta that was required by comparison with a revised model earlier.
 * The Patcher will modify the original.
 * 
 * A Patcher instance can only be used once.
 */
class Patcher {
	val List<Pair<RevisedObjectReference,Integer>> proxies = newArrayList
	val Map<ObjectDelta,EObject> patchedOriginals = newHashMap
	
	/**
	 * A special EcoreUtils.Copier that replaces object delta proxies with the patched originals they represent.
	 */	
	val copier = new Copier {
		override get(Object key) {			
			val container = (key as EObject).eContainer
			if (container instanceof ObjectDelta) {
				return patchedOriginals.get(container)
			} else {
				return super.get(key)	
			}
		}
	}
	
	private def reset() {
		copier.clear
		proxies.clear
		patchedOriginals.clear
	}
	
	/**
	 * Applies the given delta to the original. This will modify the original.
	 */
	public def patch(EObject original, ObjectDelta delta) {
		reset
		
		// associate object deltas with the original objects they represent
		saveOriginals(original, delta)				
		// recursively apply the patch
		patchSettings(original, delta)
		// copy references within the copied revised elements.		
		copier.copyReferences
		// resolve all proxies that have been found in the previous steps.
		proxies.forEach[
			val ref = it.key
			val index = it.value
			
			val value = copier.get(ref.revisedObject)
			precondition[value != null]
			
			val settingDelta = ref.eContainer.eContainer as SettingDelta
			val objectDelta = settingDelta.eContainer as ObjectDelta
			val referer = patchedOriginals.get(objectDelta)
			val feature = objectDelta.originalClass.getEStructuralFeature(settingDelta.featureID)
			
			if (feature.many) {
				val values = referer.eGet(feature) as List<EObject>
				values.set(index, value)
			} else {
				referer.eSet(feature, value)
			}
		]
	}
	
	/**
	 * Recursively populates a map that links object deltas to the original elements
	 * they represent. This has to be done, before the original is modified.
	 */
	private def void saveOriginals(EObject original, ObjectDelta objectDelta) {
		patchedOriginals.put(objectDelta, original)
		val eClass = original.eClass
		for (settingDelta:objectDelta.settingDeltas) {
			val matches = settingDelta.matchedObjects
			if (!matches.empty) {
				val feature = eClass.getEStructuralFeature(settingDelta.featureID)
				if (feature instanceof EReference) {
					if (feature.containment) {
						if (feature.many) {
							val values = original.eGet(feature) as List<EObject>
							for (match:matches) saveOriginals(values.get(match.originalIndex), match)
						} else {
							val value = original.eGet(feature)
							if (value != null) {
								precondition[matches.size == 1]
								saveOriginals(value as EObject, matches.get(0))
							}
						}
					}
				}			
			}
		}
	}
	
	private def patchSettings(EObject original, ObjectDelta objectDelta) {	
		val eClass = objectDelta.originalClass
		precondition[original.eClass == eClass]
		for(settingDelta:objectDelta.settingDeltas) {
			val feature = eClass.getEStructuralFeature(settingDelta.featureID)
			for(match:settingDelta.matchedObjects) {
				match.patchMatch(original, feature)	
			}
			if (!settingDelta.valueDeltas.empty) {
				settingDelta.valueDeltas.patchValues(original, feature)			
			}
		}
	}
	
	private def void patchMatch(ObjectDelta match, EObject original, EStructuralFeature feature) {
		val value = if (feature.many) {
			(original.eGet(feature) as List<EObject>).get(match.originalIndex)
		} else {
			original.eGet(feature) as EObject
		}
		value.patchSettings(match)
	}
	
	protected def EObject copy(EObject eObject) {
		return copier.copy(eObject)
	}
	
	private def EObject resolve(ObjectReference ref, int index) {
		return switch ref {
			OriginalObjectReference: patchedOriginals.get(ref.originalObject)
			RevisedObjectReference: {
				val eClass = ref.revisedObject.eClass
				val proxy = eClass.EPackage.EFactoryInstance.create(eClass)
				proxies += ref -> index
				proxy						
			}
			default: unreachable as EObject
		}
	}
	
	private def void patchValues(Iterable<ValuesDelta> deltas, EObject original, EStructuralFeature feature) {
		if (feature.many) {
			val originalValues = original.eGet(feature) as List<Object>
					
			val List<Object> revisedValues = newArrayList
			val List<Object> deletedOriginalValues = newArrayList
			val Collection<Object> addedOriginalValues = newHashSet
			var originalIndex = 0
			for(delta:deltas) {
				originalValues.sub(originalIndex, delta.originalStart).forEach[revisedValues+=it]
				originalValues.sub(delta.originalStart, delta.originalEnd).forEach[deletedOriginalValues+=it]
				originalIndex = delta.originalEnd
				switch delta {
					DataValuesDelta: delta.revisedValues.iterator
					ContainedObjectsDelta: delta.revisedObjectContainments.iterator.map[
						switch it {
							RevisedObjectContainment: it.revisedObject.copy
							OriginalObjectContainment: {
								val originalValue = patchedOriginals.get(it.originalObject)
								addedOriginalValues += originalValue
								originalValue								
							}
							default: unreachable as ObjectContainment
						}
					].forEach[revisedValues+=it]
					ReferencedObjectsDelta: for(ref:delta.revisedObjectReferences) {
						val value = ref.resolve(revisedValues.size)
						revisedValues += value
					}
					default: unreachable as Iterator<Object>	
				}
			}
			originalValues.sub(originalIndex, originalValues.size).forEach[revisedValues+=it]			
			
			if (feature instanceof EReference) {
				if (feature.containment) {				
					deletedOriginalValues.filter[!addedOriginalValues.contains(it)].forEach[EcoreUtil.delete(it as EObject, true)]				
				}	
			}
			originalValues.clear			
			originalValues.addAll(revisedValues)
		} else {
			val delta = deltas.iterator.next
			val patchedValue = switch(delta) {
				DataValuesDelta: if (delta.revisedValues.empty) null else delta.revisedValues.get(0)
				ContainedObjectsDelta: if (delta.revisedObjectContainments.empty) null else {
					val revisedObject = delta.revisedObjectContainments.get(0)
					switch revisedObject {
						RevisedObjectContainment: revisedObject.revisedObject.copy
						OriginalObjectContainment: patchedOriginals.get(revisedObject.originalObject) 
						default: unreachable as Object
					}
				}
				ReferencedObjectsDelta: if (delta.revisedObjectReferences.empty) {
					null
				} else {
					delta.revisedObjectReferences.get(0).resolve(-1)	
				}
			}
			if (feature instanceof EReference) {
				if (feature.containment) {
					val oldValue = original.eGet(feature)
					if (oldValue != null && oldValue != patchedValue) {
						EcoreUtil.delete(oldValue as EObject, true)
					}
				}
			}
			original.eSet(feature, patchedValue)
		}	
	}
	
	private static def Iterator<Object> sub(List<Object> data, int start, int end) {
		return new AbstractIterator<Object> {
			var index = start			
			override protected computeNext() {
				if (index < end) {
					return data.get(index++)
				} else {
					return endOfData
				}
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