package de.hub.emfcompress.tests

import de.hub.emfcompress.Comparer
import de.hub.emfcompress.EcoreComparerConfigration
import de.hub.emfcompress.Patcher
import java.io.ByteArrayInputStream
import org.eclipse.emf.common.util.URI
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EPackage
import org.eclipse.emf.ecore.EcoreFactory
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.emf.ecore.resource.Resource.Factory
import org.eclipse.emf.ecore.resource.impl.ResourceSetImpl
import org.eclipse.ocl.pivot.utilities.OCL
import org.eclipse.ocl.xtext.oclinecore.OCLinEcoreStandaloneSetup
import org.eclipse.ocl.xtext.oclinecore.utilities.OCLinEcoreCSResource
import org.junit.Before
import org.junit.Test
import de.hub.emfcompress.DefaultComparerConfigration

class BasicTests extends AbstractTests {
	
	var EMFParser testModelParser = null
	
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
	
	@Before
	public def void beforeClass() {
		val injector = new OCLinEcoreStandaloneSetup().createInjectorAndDoEMFRegistration
		Resource.Factory.Registry.INSTANCE.extensionToFactoryMap.put("oclinecore", new Factory {			
			override createResource(URI uri) {
				val resource = injector.getInstance(OCLinEcoreCSResource)
				resource.URI = uri
				return resource
			}			
		})
		
		val testMetaModel = new ResourceSetImpl().getResource(URI.createURI("model/test.ecore"), true).contents.get(0) as EPackage
		testModelParser = new EMFParser(testMetaModel) 
	}
	
	private def EObject testModel(CharSequence testModelStr) {
		return testModelParser.parse(testModelStr)
	}
	
	private def EObject ecore(String ecoreStr) {
 		val in = new ByteArrayInputStream(ecoreStr.getBytes());
		val uri = URI.createURI("dummy:/nop.ecore")
		val ocl = OCL.newInstance
		val root = ocl.as2ecore(ocl.cs2as(ocl.getCSResource(URI.createURI("test.oclinecore"), in)), uri).contents.get(0)
 		return root
	}
	
	private def newEcoreComparer() {
		return new Comparer(EcoreComparerConfigration.instance)
	}
	
	private def newDefaultComparer() {
		return new Comparer(DefaultComparerConfigration.instance)
	}
	
	def void performListTest(String[] originalNames, String[] revisedNames) {
		val original = createClass("aClass", originalNames.map[createAttribute])
		val revised = createClass("aClass", revisedNames.map[createAttribute])
		
		val delta = newEcoreComparer.compare(original, revised)
		
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
		
		performTestBothDirections(revised, original)[newEcoreComparer]
	}
	
	@Test
	def void addReplaceSingleReferenceTest() {
		val original = ecore('''
			package test : t='http://uri/1.0' {
				class A {
				}
				
				class B {
					property t:A[?];
				}
			}
		''')
		
		val revised = ecore('''
			package test : t='http://uri/1.0' {
				class C {
				}
				
				class B {
					property t:C[?];
				}
			}
		''')
		
		performTestBothDirections(revised, original)[newEcoreComparer]
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
		
		performTestBothDirections(revised, original)[newEcoreComparer]
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
		
		performTestBothDirections(revised, original)[newEcoreComparer]
	}
	
	@Test
	def void addRemoveSingleReference() {
		val original = ecore('''
			package test : t='http://uri/1.0' {
				class A {
					operation op(): A[?];
				}
			}
		''')
		
		val revised = ecore('''
			package test : t='http://uri/1.0' {
				class A {
					operation op();
				}
			}
		''')
		
		performTestBothDirections(revised, original)[newEcoreComparer]
	}
	
	@Test
	def void testReplacedReference() {
		val original = testModel('''
			TC root {
				contents = TC replaceContainer {
					contents = TC replaced {
						contents = TC referenced
					}
				}
				contents = TC refContainer {
					refs = @referenced
				}
			}
		''')
		val revised = testModel('''
			TC root {
				contents = TC replaceContainer {
					contents = TC renamed {
						contents = TC referenced
					}
				}
				contents = TC refContainer {
					refs = @referenced
				}
			}
		''')
		performTestBothDirections(revised, original)[newDefaultComparer]
	}
}