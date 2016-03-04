package de.hub.emfcompress

import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature

class EMFPrettyPrint {
	
	static def signature(EObject eObject) {
		return '''«eObject.name»[«eObject.eClass.name»]'''
	}
	
	public static def String prettyPrint(EObject eObject) {
		val features = eObject.eClass.EAllStructuralFeatures
			.filter[!isDerived && !isTransient && !isVolatile]
			.filter[eObject.eIsSet(it)]		
			.filter[eObject.eGet(it) != eObject.eContainer]	
			.filter[it.name != "name"].toList
		return if (features.empty) {
			eObject.signature
		} else {
			'''
				@«eObject.name» [«eObject.eClass.name»] {
					«FOR feature:features»
						«prettyPrint(eObject,feature)»
					«ENDFOR»
				}
			'''.toString.replace("\t", "  ")
		}	
	}
	
	private static def prettyPrint(EObject eObject, EStructuralFeature feature) {
		if (feature.many) {
			'''
				«feature.name» = [
					«FOR value: eObject.eGet(feature) as List<?>»
						«prettyPrintValue(value, feature)»
					«ENDFOR»
				]
			'''
		} else {
			'''«feature.name» = «eObject.eGet(feature)?.prettyPrintValue(feature)»'''
		}
	}
	
	private static def prettyPrintValue(Object object, EStructuralFeature feature) {
		return switch (object) {
			EObject: if ((feature as EReference).containment) {
					prettyPrint(object)
				} else {
					'''ref<«object.signature»>'''
				}
			String: object.normalize
			default: object.toString
		}
	}
	
	public static def name(EObject eObject) {
		val eClass = eObject.eClass
		val nameAttr = eClass.EAllAttributes.filter[!many].findFirst[it.name.toLowerCase == "name" || it.name.toLowerCase == "id"]
		return if (nameAttr != null)
			eObject.eGet(nameAttr)?.toString?.normalize
		else 
			""
	}
	
	public static def normalize(String str) {
		if (str.length > 32) str.substring(0, 30) + "..." else str
	}
}