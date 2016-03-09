package de.hub.emfcompress

import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EPackage
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EcorePackage
import org.eclipse.emf.ecore.util.EcoreUtil
import org.junit.Test

class EcoreTests extends AbstractTests {
	
	private def newComparer() {
		return new Comparer {		
			override protected ignore(EStructuralFeature feature) {
				if (feature == EcorePackage.eINSTANCE.EClass_EGenericSuperTypes) {
					return true
				}
				return false
			}			
		}
	}
	
	@Test
	def void renameAttributeTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="ENamedElement"] as EClass
		val feature = class.EStructuralFeatures.findFirst[name=="name"]
		feature.name = "someThingElse"
				
		performTestBothDirections(revised, original)[newComparer]
	} 
	
	@Test
	def void removeClassTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="EDataType"] as EClass
		EcoreUtil.delete(class, true)
		
		performTestBothDirections(revised, original)[newComparer]
	}
	
	@Test
	def void changeRefTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="EDataType"] as EClass
		class.ESuperTypes.add(revised.EClassifiers.findFirst[name=="ETypedElement"] as EClass)
		
		performTestBothDirections(revised, original)[newComparer]
	}
}