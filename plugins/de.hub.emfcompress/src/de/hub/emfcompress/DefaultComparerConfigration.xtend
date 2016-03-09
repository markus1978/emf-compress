package de.hub.emfcompress

import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature

class DefaultComparerConfigration implements ComparerConfiguration {
	
	public static val instance = new DefaultComparerConfigration

	protected new() {}
	
	override boolean ignore(EStructuralFeature feature) {
		return false
	}
	
	override boolean compareWithMatch(EObject original,EObject revised) {
		return original.eClass == revised.eClass && original.eClass.getEStructuralFeature("name") != null
	}
	
	override boolean match(EObject original,EObject revised) {
		val nameFeature = original.eClass.getEStructuralFeature("name")
		return original.eGet(nameFeature) == revised.eGet(nameFeature)
	} 
}