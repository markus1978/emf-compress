package de.hub.emfcompress

import com.google.common.collect.AbstractIterator
import difflib.myers.Equalizer
import java.util.Iterator
import java.util.List
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil.EqualityHelper

import static difflib.DiffUtils.*
import org.eclipse.emf.ecore.util.EcoreUtil

class EmfCompressCompare {	
	
	static val Equalizer<Object> valueEqualizer = new Equalizer<Object> {		
		override equals(Object original, Object revised) {
			return if (original == null) {
				revised == original
			} else {
				original.equals(revised)
			}
		}
	}
	
	public static def EmfObjectPatch compare(EObject original, EObject revised, Equalizer<EObject> objectEqualizer) {
		val result = new EmfObjectPatch
		for(feature:original.eClass.EAllStructuralFeatures) {
			if (!feature.derived) {
				if (feature.many) {
					val patch = if (feature instanceof EAttribute) {
						compare(feature, original.eGet(feature) as List<Object>, revised.eGet(feature) as List<Object>, valueEqualizer)					
					} else {
						compare(feature, original.eGet(feature) as List<EObject>, revised.eGet(feature) as List<EObject>, objectEqualizer)
					}
					if (patch.size != 0) {
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
						result.settingPatches += new EmfValuePatch(feature, revisedValue)
					}
				}
			}
		}
		return result
	}

	public static def <T> EmfListPatch compare(EStructuralFeature feature, List<T> original, List<T> revised, Equalizer<T> equalizer) {	
		val diffUtilsPatch = diff(original, revised, equalizer)
		
		return new EmfListPatch(feature, diffUtilsPatch.deltas.map[
			new EmfDelta(it.original.position, it.original.position + it.original.size, it.revised.lines as Iterable<Object>)
		])
	}
}

class EmfObjectPatch {
	public val List<EmfSettingPatch> settingPatches = newArrayList
	
	def EObject apply(EObject original) {		
		val revised = EcoreUtil.copy(original)
		val patchedFeatures = newHashSet
		for (settingPatch:settingPatches) {
			settingPatch.apply(original, revised)
			patchedFeatures += settingPatch.feature
		}
		return revised
	}
}

abstract class EmfSettingPatch {
	public val EStructuralFeature feature
	new(EStructuralFeature feature) {
		if (feature == null) {
			println("##")
		}	
		this.feature = feature
	}
	public abstract def void apply(EObject original, EObject revised);
}

class EmfDelta {
	public val int first
	public val int last
	public val List<Object> newContent
	
	new(int first, int last, Iterable<Object> newContent) {
		this.first = first
		this.last = last
		this.newContent = newContent.toList
	}
}

class EmfValuePatch extends EmfSettingPatch {
	Object value
	new(EStructuralFeature feature, Object value) {
		super(feature)
		this.value = value
	}

	override apply(EObject original, EObject revised) {
		revised.eSet(feature, original.eGet(feature))
	}
}

class EmfListPatch extends EmfSettingPatch {
	val List<EmfDelta> deltas
	
	new(EStructuralFeature feature, Iterable<EmfDelta> deltas) {
		super(feature)
		this.deltas = newArrayList(deltas)
	}
	
	static def <T> Iterator<T> sub(List<T> data, int start, int end) {
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
	
	/**
	 * @returns an Iterable t(a view on the given original list) that represents
	 * the patched original lists, i.e. iterates through the values of the revised list.
	 */
	override apply(EObject original, EObject revised) {
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
			result += originalValues.sub(index, delta.first).toIterable.map(copy)
			index = delta.last
			result += delta.newContent
		}
		result += originalValues.sub(index, originalValues.size).toIterable.map(copy)		
	}
	
	def size() {
		return deltas.size
	}
}

/**
 * A special Equalizer that recursively compares too object by traversing their containment hierarchy. It only
 * uses attributes and containment references to establish if they are equal or not.
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