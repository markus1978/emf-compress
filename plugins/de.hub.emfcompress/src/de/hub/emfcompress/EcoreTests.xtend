package de.hub.emfcompress

import java.io.File
import org.apache.commons.io.FileUtils
import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EPackage
import org.eclipse.emf.ecore.EcorePackage
import org.eclipse.emf.ecore.util.EcoreUtil
import org.junit.Test

import static org.junit.Assert.*

class EcoreTests {
	
	private def assertEmfEquals(EObject result, EObject goal) {	
		try {	
 			assertTrue(EcoreUtil.equals(goal, result))	
 		} catch (Throwable e) {
 			FileUtils.write(new File("testdata/goal.txt"), '''GOAL\n«EMFPrettyPrint.prettyPrint(goal)»''')
 			FileUtils.write(new File("testdata/result.txt"), '''RESULT\n«EMFPrettyPrint.prettyPrint(result)»''')
 			throw e
 		}
	}
	
	@Test
	def void renameAttributeTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="ENamedElement"] as EClass
		val feature = class.EStructuralFeatures.findFirst[name=="name"]
		feature.name = "someThingElse"
		
		assertEmfEquals(revised, original)
		
		val delta = Comparer.compare(original, revised)
		println(EMFPrettyPrint.prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	} 
	
	@Test
	def void removeClassTest() {
		val EPackage original = EcoreUtil.copy(EcorePackage.eINSTANCE)
		val revised = EcoreUtil.copy(original)
		
		val class = revised.EClassifiers.findFirst[name=="EDataType"] as EClass
		EcoreUtil.delete(class)
		
		val delta = Comparer.compare(original, revised)
		println(EMFPrettyPrint.prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	}
}