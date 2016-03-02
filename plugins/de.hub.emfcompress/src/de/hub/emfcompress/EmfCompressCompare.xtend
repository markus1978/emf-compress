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

class EmfCompressCompare {	
	public static def <T> EmfPatch<T> compare(List<T> original, List<T> revised) {
		return compare(original, revised, new EmfDefaultEqualizer)
	}

	public static def <T> EmfPatch<T> compare(List<T> original, List<T> revised, Equalizer<T> equalizer) {	
		val diffUtilsPatch = diff(original, revised, equalizer)
		
		return new EmfPatch(diffUtilsPatch.deltas.map[
			new EmfDelta(it.original.position, it.original.position + it.original.size, it.revised.lines)
		])
	}
}

class EmfDelta<T> {
	public val int first
	public val int last
	public val List<T> newContent
	
	new(int first, int last, Iterable<T> newContent) {
		this.first = first
		this.last = last
		this.newContent = newArrayList(newContent)
	}
}

class EmfPatch<T> {
	val List<EmfDelta<T>> deltas
	
	new(Iterable<EmfDelta<T>> deltas) {
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
	
	def Iterable<T> apply(List<T> original) {		
		val List<Iterable<T>> result = newArrayList
		var index = 0
		for(delta:deltas) {
			result += original.sub(index, delta.first).toIterable
			index = delta.last
			result += delta.newContent
		}
		result += original.sub(index, original.size).toIterable
		return result.flatten
	}
	
	def size() {
		return deltas.size
	}
}

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