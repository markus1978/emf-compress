package de.hub.emfcompress

import com.google.common.collect.AbstractIterator
import java.util.Iterator
import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil

class Patcher {
	
	public def patch(EObject original, DObject objectDelta) {		
		val eClass = objectDelta.originalClass
		precondition[original.eClass == eClass]
		for(settingDelta:objectDelta.settings) {
			val feature = eClass.getEStructuralFeature(settingDelta.featureID)
			for(update:settingDelta.updates) {
				update.patch(original, feature)	
			}
			settingDelta.deltas.patch(original, feature)
		}
	}
	
	private def void patch(DValueUpdate update, EObject original, EStructuralFeature feature) {
		val value = if (feature.many) {
			(original.eGet(feature) as List<EObject>).get(update.originalIndex)
		} else {
			original.eGet(feature) as EObject
		}
		value.patch(update.value)
	}
	
	protected def EObject copy(EObject eObject) {
		return EcoreUtil.copy(eObject)
	}
	
	private def void patch(Iterable<DValues> deltas, EObject original, EStructuralFeature feature) {
		val originalValues = original.eGet(feature) as List<Object>
				
		var Iterator<Object> result = newArrayList.iterator
		var index = 0
		for(delta:deltas) {
			result = result + originalValues.sub(index, delta.start)
			index = delta.end
			result = result + switch delta {
				DDataValues: delta.values.iterator
				DObjectValues: delta.values.iterator.map[it.copy]
				default: unreachable as Iterator<Object>	
			}
		}
		result = result + originalValues.sub(index, originalValues.size)
		
		val revisedValues = result.toList
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