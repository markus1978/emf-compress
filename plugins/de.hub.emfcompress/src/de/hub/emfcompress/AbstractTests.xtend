package de.hub.emfcompress

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
				if (EmfCompressPackage.eINSTANCE.DSetting_FeatureID == feature) {
					return ((container as DSetting).eContainer as DObject).originalClass.getEStructuralFeature(value as Integer).name
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
}