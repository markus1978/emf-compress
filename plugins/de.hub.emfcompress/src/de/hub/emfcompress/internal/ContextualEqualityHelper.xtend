package de.hub.emfcompress.internal

import java.util.Collection
import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.util.EcoreUtil

/**
 * A special EcoreUtils.EqualityHelper that compares to object in a given context. This
 * means that object are not only compared by themselves, but depending on the
 * hierarchy they are contained. it. Two equal objects are considered unequal, when 
 * their containers are not equal.
 */
// TODO this things need to be reimplemented.
abstract class ContextualEqualityHelper extends EcoreUtil.EqualityHelper {
	
	val Collection<EObject> originalsWithNoEqual = newHashSet
	
	/**
	 * Callback that must be implemented by clients to define the context. It
	 * does two things simultaneously. First, it determines if the given objects
	 * are context objects. Second, it determines if given context objects
	 * are considered equal.
	 * 
	 * @returns null, if the given objects are not yet part of the context, true if
	 * they are context objects and are considered equal, false if they are context
	 * objects that are not considered equal.
	 */
	protected abstract def Boolean contextEquals(EObject original, EObject revised);
	
	private def boolean compareContainedObjects(EObject original, EObject revised) {
		if (originalsWithNoEqual.contains(original)) {
			return false
		}
		
		val contextEquals = contextEquals(original, revised)
		if (contextEquals != null && contextEquals) {
			return true
		}
		
		val result = super.equals(original, revised)
		if (!result) {
			originalsWithNoEqual.add(original)
			original.eAllContents.forEach[originalsWithNoEqual.add(it)]
		}
		result
	}	
	
	/**
	 * Determine if the given objects are contained at the same position in the
	 * containment tree of their respective contexts and whether these contexts
	 * are equal themselves.
	 */
	private def boolean haveEqualContext(EObject original, EObject revised) {
		val contextEquals = contextEquals(original, revised)
		if (contextEquals != null) {
			return contextEquals
		} else {
			// this are not context objects
			if (original.eContainmentFeature == revised.eContainmentFeature) {
				val containmentFeature = original.eContainingFeature
				val originalContainer = original.eContainer
				val revisedContainer = revised.eContainer
				
				if (containmentFeature.many) {
					val originalIndex = (originalContainer.eGet(containmentFeature) as List<EObject>).indexOf(original)
					val revisedIndex = (revisedContainer.eGet(containmentFeature) as List<EObject>).indexOf(revised)
					if (originalIndex != revisedIndex) {
						return false
					}
				}
				
				if (haveEqualContext(originalContainer, revisedContainer)) {
					return compareContainedObjects(original, revised)
				} else {
					return false
				}			
			} else {
				return false
			}			
		}
	}
	
	private def boolean compareReferencedObjects(EObject original, EObject revised) {
		if (originalsWithNoEqual.contains(original)) {
			return false
		}
		if (get(original) == revised) {
			return true
		} else if (haveEqualContext(original, revised)) {
			return compareContainedObjects(original, revised)
		} else {
			return false			
		}	
	}

	public def boolean compareObjects(EObject original, EObject revised, boolean isContainmentCompare) {
		if (isContainmentCompare) {
			return compareContainedObjects(original, revised)							
		} else {
			return compareReferencedObjects(original, revised)
		}						
	}
	
	override equals(EObject eObject1, EObject eObject2) {
		return compareContainedObjects(eObject1, eObject2)
	}
	
	override protected haveEqualReference(EObject eObject1, EObject eObject2, EReference reference) {
		val value1 = eObject1.eGet(reference);
  		val value2 = eObject2.eGet(reference);

  		if (reference.many) { 
      		equals(value1 as List<EObject>, value2 as List<EObject>, reference)
      	} else {
      		compareObjects(value1 as EObject, value2 as EObject, reference.containment)      		
      	}
	}
	
	private def boolean equals(List<EObject> list1, List<EObject> list2, EReference reference) {
		val size = list1.size();
		if (size != list2.size()) {
			false
		} else {
	      	for (i:0..<size) {
	      		if (!compareObjects(list1.get(i), list2.get(i), reference.containment)) {
	      			return false
	      		}
	      	}
	      	true			      	
	    }			
	}
}