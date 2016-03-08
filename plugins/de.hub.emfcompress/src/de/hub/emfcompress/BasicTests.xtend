package de.hub.emfcompress

import com.google.inject.Injector
import java.io.ByteArrayInputStream
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EcoreFactory
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.Resource.Factory
import org.eclipse.ocl.pivot.utilities.OCL
import org.eclipse.ocl.xtext.oclinecore.OCLinEcoreStandaloneSetup
import org.eclipse.ocl.xtext.oclinecore.utilities.OCLinEcoreCSResource
import org.junit.BeforeClass
import org.junit.Test

import static de.hub.emfcompress.BasicTests.*
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EcorePackage

class BasicTests extends AbstractTests {
	
	static var Injector injector = null
	
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
	
	@BeforeClass
	public static def void beforeClass() {
		injector = new OCLinEcoreStandaloneSetup().createInjectorAndDoEMFRegistration
		Resource.Factory.Registry.INSTANCE.extensionToFactoryMap.put("oclinecore", new Factory {			
			override createResource(URI uri) {
				val resource = injector.getInstance(OCLinEcoreCSResource)
				resource.URI = uri
				return resource
			}			
		})
	}
	
	private def EObject ecore(String ecoreStr) {
 		val in = new ByteArrayInputStream(ecoreStr.getBytes());
		val uri = URI.createURI("dummy:/nop.ecore")
		val ocl = OCL.newInstance
		val root = ocl.as2ecore(ocl.cs2as(ocl.getCSResource(URI.createURI("test.oclinecore"), in)), uri).contents.get(0)
 		return root
	}
	
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
	
	def void performListTest(String[] originalNames, String[] revisedNames) {
		val original = createClass("aClass", originalNames.map[createAttribute])
		val revised = createClass("aClass", revisedNames.map[createAttribute])
		
		val delta = newComparer.compare(original, revised)
		
		println(prettyPrint(delta))
		new Patcher().patch(original, delta)		
		assertEmfEquals(revised, original)
	}
	
	def void performTest(EObject original, EObject revised) {
		val delta = newComparer.compare(original, revised)
		
		println(prettyPrint(delta))
		new Patcher().patch(original, delta)
		val patched = original		
		assertEmfEquals(patched, revised)
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
	
	@Test
	def void addRemoveReferenceTest() {
		val original = ecore('''
			package test : t='http://uri/1.0' {
				class A {
				}
				
				class B {
				}
			}
		''')
		
		val revised = ecore('''
			package test : t='http://uri/1.0' {
				class A {
				}
				
				class B extends A {
					
				}
			}
		''')
		
		performTest(original, revised)
		performTest(revised, original)
	}
	
	@Test
	def void addRemoveReferenceToMatchedTargetTest() {
		val original = ecore('''
			package test : t='http://uri/1.0' {
				datatype D;
				class A {
				}
				
				class B {
				}
			}
		''')
		
		val revised = ecore('''
			package test : t='http://uri/1.0' {
				datatype D;
				class A {
					attribute A: D[?];
				}
				
				class B extends A {
					
				}
			}
		''')
		
		performTest(original, revised)
		performTest(revised, original)
	}
	
	@Test
	def void addRemoveReferenceToNewTargetTest() {
		val original = ecore('''
			package test : t='http://uri/1.0' {
				class A {
				}
				
				class B {
				}
			}
		''')
		
		val revised = ecore('''
			package test : t='http://uri/1.0' {
				class C {
				}
				
				class B extends C {
				}
			}
		''')
		
		performTest(original, revised)
		performTest(revised, original)
	}
}