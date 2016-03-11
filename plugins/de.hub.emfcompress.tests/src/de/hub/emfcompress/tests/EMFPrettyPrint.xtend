package de.hub.emfcompress.tests

import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import java.util.Map

class EMFPrettyPrint {
	
	protected def String additionalValueDescription(EObject container, EStructuralFeature feature, Object value) {
		return null
	}
	
	var i = 0
	val Map<EObject,Integer> ids = newHashMap
	
	def int id(EObject eObject) {
		val existingId = ids.get(eObject)
		if (existingId != null) {
			return existingId
		} else {
			val newId = Integer.valueOf(i++)
			ids.put(eObject, newId)
			return newId
		}
	}
	
	def signature(EObject eObject) {
		return '''«eObject.name»:«eObject.id»[«eObject.eClass.name»]'''
	}
	
	public def String prettyPrint(EObject eObject) {
		val features = eObject.eClass.EAllStructuralFeatures
			.filter[!isDerived && !isTransient && !isVolatile]
			.filter[eObject.eIsSet(it)]		
			.filter[eObject.eGet(it) != eObject.eContainer]	
			.filter[it.name != "name"].toList
		return if (features.empty) {
			eObject.signature
		} else {
			'''
				@«eObject.signature» {
					«FOR feature:features»
						«prettyPrint(eObject,feature)»
					«ENDFOR»
				}
			'''.toString.replace("\t", "  ")
		}	
	}
	
	private def prettyPrint(EObject eObject, EStructuralFeature feature) {
		if (feature.many) {
			'''
				«feature.name» = [
					«FOR value: eObject.eGet(feature) as List<?>»
						«val additional = additionalValueDescription(eObject, feature, value)»
						«prettyPrintValue(value, feature)» «IF additional!=null»(«additional»)«ENDIF»
					«ENDFOR»
				]
			'''
		} else {
			val value = eObject.eGet(feature)
			val additional = if (value != null) additionalValueDescription(eObject, feature, value) else null
			'''«feature.name» = «value?.prettyPrintValue(feature)» «IF additional!=null»(«additional»)«ENDIF»'''
		}
	}
	
	private def prettyPrintValue(Object object, EStructuralFeature feature) {
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
	
	public def name(EObject eObject) {
		val eClass = eObject.eClass
		val nameAttr = eClass.EAllAttributes.filter[!many].findFirst[it.name.toLowerCase == "name" || it.name.toLowerCase == "id"]
		return if (nameAttr != null)
			eObject.eGet(nameAttr)?.toString?.normalize
		else 
			""
	}
	
	public def normalize(String str) {
		if (str.length > 32) str.substring(0, 30) + "..." else str
	}
}