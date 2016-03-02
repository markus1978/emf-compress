package de.hub.emfcompress

import difflib.DiffUtils
import java.util.List
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EcoreFactory
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
	
	private def <T extends EObject> void assertEmfEquals(List<T> one, List<T> two) {
		assertTrue(DiffUtils.diff(one, two, new EmfContainmentEqualizer<T>).deltas.size == 0)
	}
	
	@Test
	def removeStartTest() {
		val original = createClass("aClass", #["a", "b", "c"].map[createAttribute])
		val revised = createClass("aClass", #["b", "c"].map[createAttribute])
		
		val patch = EmfCompressCompare.compare(original.EAttributes, revised.EAttributes, new EmfContainmentEqualizer)
		assertSame(1, patch.size)
		assertEmfEquals(revised.EAttributes, patch.apply(original.EAttributes).toList)
	}
	
	@Test
	def removeMiddleTest() {
		val original = createClass("aClass", #["a", "b", "c"].map[createAttribute])
		val revised = createClass("aClass", #["a", "c"].map[createAttribute])
		
		val patch = EmfCompressCompare.compare(original.EAttributes, revised.EAttributes, new EmfContainmentEqualizer)
		assertSame(1, patch.size)
		assertEmfEquals(revised.EAttributes, patch.apply(original.EAttributes).toList)
	}
	
	@Test
	def removeEndTest() {
		val original = createClass("aClass", #["a", "b", "c"].map[createAttribute])
		val revised = createClass("aClass", #["a", "b"].map[createAttribute])
		
		val patch = EmfCompressCompare.compare(original.EAttributes, revised.EAttributes, new EmfContainmentEqualizer)
		assertSame(1, patch.size)
		assertEmfEquals(revised.EAttributes, patch.apply(original.EAttributes).toList)
	}
	
	@Test
	def basicTest() {
		val original = createClass("aClass", #["a", "b", "c"].map[createAttribute])
		val revised = createClass("aClass", #["b", "d", "c", "e"].map[createAttribute])
		
		val patch = EmfCompressCompare.compare(original.EAttributes, revised.EAttributes, new EmfContainmentEqualizer)
		assertSame(3, patch.size)
		assertEmfEquals(revised.EAttributes, patch.apply(original.EAttributes).toList)
	}
	
	
}