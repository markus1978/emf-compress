package de.hub.emfcompress

import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EcoreFactory
import org.eclipse.emf.ecore.util.EcoreUtil
import org.junit.Test

import static org.junit.Assert.*
import org.junit.Before

class BasicTests {
	
	var extension EmfCompressCompare compare = null
	
	@Before
	public def void init() {
		compare = new EmfCompressCompare(EmfCompressFactory.eINSTANCE, new EmfContainmentEqualizer)
	}
	
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
	
	private def <T> void assertEmfEquals(EObject one, EObject two) {
		assertTrue(EcoreUtil.equals(one, two))
	}
	
	def performListTest(String[] originalNames, String[] revisedNames) {
		val original = createClass("aClass", originalNames.map[createAttribute])
		val revised = createClass("aClass", revisedNames.map[createAttribute])
		val revisedCopy = EcoreUtil.copy(revised)
		
		val patch = compare(original, revised)
		assertEmfEquals(revisedCopy, patch.apply(original))
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