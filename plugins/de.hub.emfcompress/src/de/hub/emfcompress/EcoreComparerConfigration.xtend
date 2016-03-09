package de.hub.emfcompress

import org.eclipse.emf.ecore.ENamedElement
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EcorePackage

class EcoreComparerConfigration implements ComparerConfiguration {
	
	public static val instance = new EcoreComparerConfigration

	protected new() {}
	
	override boolean ignore(EStructuralFeature feature) {
		if (feature == EcorePackage.eINSTANCE.EClass_EGenericSuperTypes) {
			return true
		} else if (feature == EcorePackage.eINSTANCE.ETypedElement_EGenericType) {
			return true
		}
		return false
	}
	
	override boolean compareWithMatch(EObject original,EObject revised) {
		return original.eClass == revised.eClass && ENamedElement.isAssignableFrom(original.class)
	}
	
	override boolean match(EObject original,EObject revised, (EObject,EObject)=>boolean match) {
		val nameFeature = EcorePackage.eINSTANCE.ENamedElement_Name
		return original.eGet(nameFeature) == revised.eGet(nameFeature)
	} 
}