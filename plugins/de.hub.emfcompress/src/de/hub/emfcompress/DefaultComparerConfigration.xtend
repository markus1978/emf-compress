package de.hub.emfcompress

import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EReference

class DefaultComparerConfigration implements ComparerConfiguration {
	
	public static val instance = new DefaultComparerConfigration

	protected new() {}
	
	override boolean ignore(EStructuralFeature feature) {
		return false
	}
	
	override boolean match(EObject original,EObject revised, (EObject,EObject)=>boolean match) {
		val nameFeature = original.eClass.getEStructuralFeature("name")
		return original.eGet(nameFeature) == revised.eGet(nameFeature)
	}
	
	override compareWithMatch(EClass eClass, EReference reference) {
		return reference.containment && (reference.EType as EClass).getEStructuralFeature("name") != null
	}
	
}