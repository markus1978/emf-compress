package de.hub.emfcompress

import com.google.common.collect.AbstractIterator
import difflib.myers.Equalizer
import java.util.Iterator
import java.util.List
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil
import org.eclipse.emf.ecore.util.EcoreUtil.EqualityHelper

import static difflib.DiffUtils.*

class EmfCompressCompare {	
	
	val EmfCompressFactory factory
	val Equalizer<EObject> objectEqualizer
	
	val Equalizer<Object> valueEqualizer = new Equalizer<Object> {		
		override equals(Object original, Object revised) {
			return if (original == null) {
				revised == original
			} else {
				original.equals(revised)
			}
		}
	}
	
	new(EmfCompressFactory factory, Equalizer<EObject> objectEqualizer) {
		this.objectEqualizer = objectEqualizer
		this.factory = factory
	}
	
	public def ObjectPatch compare(EObject original, EObject revised) {
		val result = factory.createObjectPatch
		for(feature:original.eClass.EAllStructuralFeatures) {
			if (!feature.derived) {
				if (feature.many) {
					val patch = if (feature instanceof EAttribute) {
						compareValues(original, revised, feature, valueEqualizer) [
							val delta = factory.createValueDelta
							delta.values += it
							return delta
						]					
					} else {
						compareValues(original, revised, feature, objectEqualizer) [
							val delta = factory.createObjectDelta
							delta.objects += it
							return delta
						]
					}
					if (patch.deltas.size != 0) {
						result.settingPatches += patch
					}
				} else {
					val originalValue = original.eGet(feature)
					val revisedValue = revised.eGet(feature)
					val changed = if (originalValue == null) {
						revisedValue != originalValue
					} else {
						!originalValue.equals(revisedValue)
					}
					if (changed) {
						val patch = if (feature instanceof EReference) {
							val patch = factory.createObjectValuePatch
							patch.object = revisedValue as EObject
							patch							
						} else {
							val patch = factory.createDataValuePatch
							patch.value = revisedValue
							patch
						}
						result.settingPatches += patch
					}
				}
			}
		}
		return result
	}

	public def <T> ListPatch compareValues(EObject original, EObject revised, EStructuralFeature feature, Equalizer<T> equalizer, (Iterable<T>)=> Delta createDelta) {	
		val diffUtilsPatch = diff(original.eGet(feature) as List<T>, revised.eGet(feature) as List<T>, equalizer)
		val result = factory.createListPatch
		result.featureID = original.eClass.getFeatureID(feature)
		result.deltas += diffUtilsPatch.deltas.map[
			val delta = createDelta.apply(it.revised.lines)
			delta.start = it.original.position
			delta.end = it.original.position + it.original.size
			return delta
		]
		return result
	}
	
	public def apply(extension ObjectPatch patch, EObject original) {
		val revised = EcoreUtil.copy(original)
		for (settingPatch:settingPatches) {
			settingPatch.applySettingsPatch(original, revised)
		}
		return revised
	}
	
	private dispatch def void applySettingsPatch(extension ListPatch patch, EObject original, EObject revised) {
		val feature = original.eClass.getEStructuralFeature(featureID)
		val (Object)=>Object copy = [
			if (feature instanceof EReference) {
				if (feature.containment) {
					return EcoreUtil.copy(it as EObject)
				}
			} 
			return it
		]
		
		val originalValues = original.eGet(feature) as List<Object>
				
		val List<Object> result = revised.eGet(feature) as List<Object>
		result.clear
		var index = 0
		for(delta:deltas) {
			result += originalValues.sub(index, delta.start).toIterable.map(copy)
			index = delta.end
			result += if (delta instanceof ObjectDelta) {
				delta.objects				
			} else {
				(delta as ValueDelta).values
			}
		}
		result += originalValues.sub(index, originalValues.size).toIterable.map(copy)	
	}
	
	private dispatch def void applySettingsPatch(extension ValuePatch patch, EObject original, EObject revised) {
		val feature = original.eClass.getEStructuralFeature(featureID)
		revised.eSet(feature, if (patch instanceof ObjectValuePatch) { 
			patch.object
		} else { 
			(patch as DataValuePatch).value
		})
	}
	
	private static def <T> Iterator<T> sub(List<T> data, int start, int end) {
		return new AbstractIterator<T> {
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
}

/**
 * A special Equalizer that recursively compares too object by traversing their containment hierarchy. It only
 * uses attributes and containment references to establish if objects are equal or not.
 */
class EmfContainmentEqualizer<T extends EObject> extends EmfDefaultEqualizer<T> {
	new() {
		super(new EqualityHelper() {
			
			override protected haveEqualFeature(EObject eObject1, EObject eObject2, EStructuralFeature feature) {
				return if (feature instanceof EAttribute) {
					super.haveEqualFeature(eObject1, eObject2, feature)	
				} else if ((feature as EReference).containment) {
					super.haveEqualFeature(eObject1, eObject2, feature)
				} else {
					true
				}				
			}			
		})
	}
}

class EmfDefaultEqualizer<T extends EObject> implements Equalizer<T> {
	val EqualityHelper equalityHelper
	new() {
		this.equalityHelper = new EqualityHelper
	}
	new(EqualityHelper helper) {
		this.equalityHelper = helper
	}
	override equals(T one, T two) {
		val result = equalityHelper.equals(one, two)
		return result
	}
}