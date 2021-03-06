package de.hub.emfcompress.tests

import de.hub.emfcompress.Comparer
import de.hub.emfcompress.EmfCompressFactory
import de.hub.emfcompress.EmfCompressPackage
import de.hub.emfcompress.ObjectDelta
import de.hub.emfcompress.Patcher
import de.hub.emfcompress.SettingDelta
import java.io.File
import org.apache.commons.io.FileUtils
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil

import static org.junit.Assert.*

class AbstractTests {
	
	protected def prettyPrint(EObject eObject) {
		val printer = new EMFPrettyPrint {			
			override protected additionalValueDescription(EObject container, EStructuralFeature feature, Object value) {
				if (EmfCompressPackage.eINSTANCE.settingDelta_FeatureID == feature) {
					return ((container as SettingDelta).eContainer as ObjectDelta).originalClass.getEStructuralFeature(value as Integer).name
				}
			}			
		}
		return printer.prettyPrint(eObject)
	}
	
	protected def assertEmfEquals(EObject result, EObject goal) {	
		try {	
 			assertTrue(EcoreUtil.equals(goal, result))	
 		} catch (Throwable e) {
 			FileUtils.write(new File("testdata/goal.txt"), '''GOAL\n«prettyPrint(goal)»''')
 			FileUtils.write(new File("testdata/result.txt"), '''RESULT\n«prettyPrint(result)»''')
 			throw e
 		}
	}
	
	def void performTest(Comparer comparer, EObject original, EObject revised) {
		val delta = comparer.compare(original, revised)
		val patched = EcoreUtil.copy(original)
		
		try {
			new Patcher(EmfCompressFactory.eINSTANCE).patch(patched, delta)	
			assertEmfEquals(patched, revised)		
		} catch (Throwable e) {
			println(prettyPrint(delta))	
			throw e
		}
	}
	
	def void performTestBothDirections(EObject original, EObject revised, ()=>Comparer newComparer) {
		performTest(newComparer.apply, original, revised)
		performTest(newComparer.apply, revised, original)
	}
}