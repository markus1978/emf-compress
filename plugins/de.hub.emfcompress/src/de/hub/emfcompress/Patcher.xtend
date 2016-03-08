package de.hub.emfcompress

import com.google.common.collect.AbstractIterator
import java.util.Iterator
import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil.Copier
import org.eclipse.emf.ecore.EReference

class Patcher {
	val List<Pair<DRevisedObjectReference,Integer>> proxies = newArrayList	
	val copier = new Copier {
		override get(Object key) {			
			val container = (key as EObject).eContainer
			if (container instanceof DObject) {
				return container.transientOriginal
			} else {
				return super.get(key)	
			}
		}
	}
	
	public def patch(EObject original, DObject delta) {
		saveOriginals(original, delta)				
		patchContainment(original, delta)		
		copier.copyReferences
		proxies.forEach[
			val ref = it.key
			val index = it.value
			
			val value = copier.get(ref.value)
			precondition[value != null]
			
			val settingDelta = ref.eContainer.eContainer as DSetting
			val objectDelta = settingDelta.eContainer as DObject
			val referer = objectDelta.transientOriginal
			val feature = objectDelta.originalClass.getEStructuralFeature(settingDelta.featureID)
			
			if (feature.many) {
				val values = referer.eGet(feature) as List<EObject>
				values.set(index, value)
			} else {
				referer.eSet(feature, value)
			}
		]
	}
	
	private def void saveOriginals(EObject original, DObject objectDelta) {
		objectDelta.transientOriginal = original
		val eClass = original.eClass
		for (settingDelta:objectDelta.settings) {
			val matches = settingDelta.matches
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
	
	private def patchContainment(EObject original, DObject objectDelta) {	
		val eClass = objectDelta.originalClass
		precondition[original.eClass == eClass]
		for(settingDelta:objectDelta.settings) {
			val feature = eClass.getEStructuralFeature(settingDelta.featureID)
			for(match:settingDelta.matches) {
				match.patch(original, feature)	
			}
			settingDelta.deltas.patch(original, feature)
		}
	}
	
	private def void patch(DObject match, EObject original, EStructuralFeature feature) {
		val value = if (feature.many) {
			(original.eGet(feature) as List<EObject>).get(match.originalIndex)
		} else {
			original.eGet(feature) as EObject
		}
		value.patchContainment(match)
	}
	
	protected def EObject copy(EObject eObject) {
		return copier.copy(eObject)
	}
	
	private def void patch(Iterable<DValues> deltas, EObject original, EStructuralFeature feature) {
		val originalValues = original.eGet(feature) as List<Object>
				
		val List<Object> revisedValues = newArrayList
		var originalIndex = 0
		for(delta:deltas) {
			originalValues.sub(originalIndex, delta.start).forEach[revisedValues+=it]
			originalIndex = delta.end
			switch delta {
				DDataValues: delta.values.iterator
				DContainedObjectValues: delta.values.iterator.map[it.copy].forEach[revisedValues+=it]
				DReferencedObjectValues: for(ref:delta.references) {
					val value = switch ref {
						DOriginalObjectReference: ref.value.transientOriginal
						DRevisedObjectReference: {
							val eClass = ref.value.eClass
							val proxy = eClass.EPackage.EFactoryInstance.create(eClass)
							proxies += ref -> revisedValues.size
							proxy						
						}
						default: unreachable as EObject
					}
					revisedValues += value
				}
				default: unreachable as Iterator<Object>	
			}
		}
		originalValues.sub(originalIndex, originalValues.size).forEach[revisedValues+=it]
		
		originalValues.clear
		originalValues.addAll(revisedValues)	
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