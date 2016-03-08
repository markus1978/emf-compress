package de.hub.emfcompress

import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EPackage
import org.eclipse.emf.ecore.EcorePackage
import org.eclipse.emf.ecore.util.EcoreUtil
import org.junit.Test

class EcoreTests extends AbstractTests {
	
	@Test
	def void renameAttributeTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="ENamedElement"] as EClass
		val feature = class.EStructuralFeatures.findFirst[name=="name"]
		feature.name = "someThingElse"
		
		assertEmfEquals(revised, original)
		
		val delta = new Comparer().compare(original, revised)
		println(prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	} 
	
	@Test
	def void removeClassTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="EDataType"] as EClass
		EcoreUtil.delete(class)
		
		val delta = new Comparer().compare(original, revised)
		println(prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	}
}