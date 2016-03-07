package de.hub.emfcompress

import java.io.File
import org.apache.commons.io.FileUtils
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EcoreFactory
import org.eclipse.emf.ecore.util.EcoreUtil
import org.junit.Test

import static org.junit.Assert.*

class BasicTests {
	
	private def createAttribute(String name) {
		val content = EcoreFactory.eINSTANCE.createEAttribute
		content.name = name
		return content
	}
	
	private def createClass(String name, Iterable<EAttribute> content) {
		val container = EcoreFactory.eINSTANCE.createEClass
		container.name = name
		content.forEach[container.EStructuralFeatures += it]
		return container
	}
	
	private def assertEmfEquals(EObject result, EObject goal) {	
		try {	
 			assertTrue(EcoreUtil.equals(goal, result))	
 		} catch (Throwable e) {
 			FileUtils.write(new File("testdata/goal.txt"), '''GOAL\n«EMFPrettyPrint.prettyPrint(goal)»''')
 			FileUtils.write(new File("testdata/result.txt"), '''RESULT\n«EMFPrettyPrint.prettyPrint(result)»''')
 			throw e
 		}
	}
	
	def void performListTest(String[] originalNames, String[] revisedNames) {
		val original = createClass("aClass", originalNames.map[createAttribute])
		val revised = createClass("aClass", revisedNames.map[createAttribute])
		
		val delta = Comparer.compare(original, revised)
		
		println(EMFPrettyPrint.prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	}
	
	@Test
	def removeStartTest() {
		performListTest(#["a", "b", "c"], #["b", "c"])
	}
	
	@Test
	def removeMiddleTest() {
		performListTest(#["a", "b", "c"], #["a", "c"])
	}
	
	@Test
	def removeEndTest() {
		performListTest(#["a", "b", "c"], #["a", "b"])
	}
	
	@Test
	def addStartTest() {
		performListTest(#["b", "c"], #["a", "b", "c"])
	}
	
	@Test
	def addMiddleTest() {
		performListTest(#["a", "c"], #["a", "b", "c"])
	}
	
	@Test
	def addEndTest() {
		performListTest(#["a", "b"], #["a", "b", "c"])
	}
	
	@Test
	def mixedTest() {
		performListTest(#["a", "b", "c"], #["e", "b", "c"])
	}
}