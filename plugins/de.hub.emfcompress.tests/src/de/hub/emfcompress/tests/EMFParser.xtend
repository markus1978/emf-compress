package de.hub.emfcompress.tests

import java.util.List
import org.codehaus.jparsec.Parser
import org.codehaus.jparsec.Parsers
import org.codehaus.jparsec.Terminals
import org.eclipse.emf.ecore.EClass
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EPackage

import static org.codehaus.jparsec.Parsers.*
import static org.codehaus.jparsec.Terminals.*
import org.codehaus.jparsec.Scanners
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.InternalEObject
import org.eclipse.emf.common.util.URI

class EMFParser {
	
	val EPackage metaModel
	
	val terminals = operators("{", "}", "=", "[", "]", ",", "@");
	val id = Terminals.Identifier.TOKENIZER
	val tokenizer = Parsers.<Object>or(terminals.tokenizer(), id)
	
	new(EPackage metaModel) {
		this.metaModel = metaModel
	}
	
	public def EObject parse(CharSequence content) {
		val model = parser.parse(content)
		val names = newHashMap
		val (EObject)=>void addName = [
			val nameFeature = it.eClass.getEStructuralFeature("name")
			if (nameFeature != null) {
				val name = it.eGet(nameFeature)
				if (name != null) {
					names.put(name, it)
				}
			}
		]
		val (EObject)=>EObject resolve = [
			if (eIsProxy) {
				val name = (it as InternalEObject).eProxyURI.toString
				names.get(name)
			} else {
				it
			}
		]
		val (EObject)=>void resolveProxyReferences = [
			for(ref:it.eClass.EAllReferences.filter[!containment]) {
				if (ref.many) {
					val values = eGet(ref) as List<EObject>
					for(i:0..<values.size) {
						values.set(i, resolve.apply(values.get(i)))
					}
				} else {
					if (eIsSet(ref)) {
						eSet(ref, resolve.apply(eGet(ref) as EObject))
					}
				}
			}
		]
		addName.apply(model)
		model.eAllContents.forEach(addName)
		
		resolveProxyReferences.apply(model)
		model.eAllContents.forEach(resolveProxyReferences)
		
		model
	}
	
	static def EObject parse(EPackage metaModel, CharSequence content) {
		new EMFParser(metaModel).parse(content)
	}
	
	def Parser<EObject> parser() {
		object.from(tokenizer.lexer(Scanners.WHITESPACES.many))
	}
	
	private def Parser<Pair<String, List<Object>>> setting(Parser<EObject> object) {
		or(manySetting(object), singleSetting(object))
	}
	
	private def Parser<Pair<String, List<Object>>> manySetting(Parser<EObject> object) {
		array(identifier, terminals.token("="), terminals.token("["), value(object).atLeast(0), terminals.token("]")).map[
			get(0) as String -> get(3) as List<Object> 
		]
	}
	
	private def Parser<Pair<String, List<Object>>> singleSetting(Parser<EObject> object) {
		array(identifier, terminals.token("="), value(object)).map[
			get(0) as String -> #[get(2)] 
		]
	}
	
	private def Parser<Object> value(Parser<EObject> object) {
		or(object,reference)
	}
	
	private def Parser<Object> reference() {
		or(
			array(terminals.token("@"), identifier, terminals.token("["), identifier, terminals.token("]")).map[get(1)->get(3)],
			array(terminals.token("@"), identifier).map[get(1)->null]
		)
	}
	
	private def Parser<List<Pair<String,List<Object>>>> settings(Parser<EObject> object) {
		or(
			array(terminals.token("{"), setting(object).atLeast(0), terminals.token("}")).map[
				it.get(1) as List<Pair<String,List<Object>>>
			],
			array().map[#[]]	
		)
		
	}
	
	private def Object proxyValue(EStructuralFeature feature, Object value) {
		if (feature instanceof EReference) {
			if (!feature.containment) {
				val ref = value as Pair<String,String>
				val eClass = if (ref.value == null) {
					feature.EType as EClass
				} else {
					metaModel.getEClassifier(ref.value) as EClass
				}
				val proxy = metaModel.EFactoryInstance.create(eClass);
				(proxy as InternalEObject).eSetProxyURI(URI.createURI(ref.key))
				return proxy
			}
		}
		return value
	}
	
	private def Parser<EObject> object() {
		val Parser.Reference<EObject> ref = Parser.newReference();
		val parser = array(identifier, identifier, settings(ref.lazy)).map[
			val eClass = metaModel.getEClassifier(it.get(0) as String) as EClass
			val eObject = metaModel.EFactoryInstance.create(eClass)
			for(setting:it.get(2) as List<Pair<String,List<Object>>>) {
				val eFeature = eClass.getEStructuralFeature(setting.key)
				if (eFeature.many) {
					val values = eObject.eGet(eFeature) as List<Object>
					for(value:setting.value) {
						values.add(eFeature.proxyValue(value))
					}
				} else {
					if (!setting.value.empty) {
						eObject.eSet(eFeature, eFeature.proxyValue(setting.value.get(0)))
					}
				}
			}
			val nameFeature = eClass.getEStructuralFeature("name")
			if (nameFeature != null) {
				eObject.eSet(nameFeature, it.get(1))
			}
			eObject
		]	
		ref.set(parser)
		parser
	}
}