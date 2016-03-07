package de.hub.emfcompress

import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EReference
import java.util.Map
import java.util.List
import difflib.DiffUtils
import org.eclipse.emf.ecore.util.EcoreUtil
import org.eclipse.emf.ecore.util.EcoreUtil.Copier

enum MatchType { different, match, equal }

class Comparer {
	
	val factory = EmfCompressFactory.eINSTANCE
	val Map<Pair<EObject,EObject>,MatchType> matches = newHashMap
	val copier = new Copier
	
	public static def DObject compare(EObject original, EObject revised) {
		val comparer = new Comparer()
		val delta = comparer.compareContainment(original, revised)
		
		return delta		
	}
	
	private def DObject compareContainment(EObject original, EObject revised) {
		precondition[original.eClass == revised.eClass]
		
		val eClass = original.eClass	
		val List<DSetting> settingDeltas = newArrayList	
		for(feature:eClass.EAllStructuralFeatures) {
			if (feature.changeable && !feature.derived && (feature instanceof EAttribute || (feature as EReference).containment)) {
				val List<DValues> valueDeltas = newArrayList
				val List<DValueMatch> matches = newArrayList
				val (EObject,EObject)=> void onMatched = [matchedOriginal, matchedRevised|
					val delta = compare(matchedOriginal, matchedRevised)
					if (delta != null) {
						val match = factory.createDValueMatch
						match.originalIndex = if (feature.many) {
							(original.eGet(feature) as List<Object>).indexOf(matchedOriginal) // TODO
						} else {
							-1
						}
						match.value = delta
						matches += match
					}
				]				 				
				if (feature.many) {
					val originalValues = original.eGet(feature) as List<Object>
					val revisedValues = revised.eGet(feature) as List<Object>
					val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
						compare(comparedOriginal,comparedRevised,feature,onMatched) 
					]
					if (!patch.deltas.empty) {
						valueDeltas += patch.deltas.map[
							val replacedValues = switch feature {
								EAttribute: {
									val replacedDataValues = factory.createDDataValues
									it.revised.lines.forEach[replacedDataValues.values += it]
									replacedDataValues							
								}
								EReference: {
									val replacedObjectValues = factory.createDContainedObjectValues
									it.revised.lines.forEach[replacedObjectValues.values += copy(it as EObject)]
									replacedObjectValues
								}
								default: unreachable as DValues
							}
							replacedValues.start = it.original.position
							replacedValues.end = it.original.position + it.original.size
							return replacedValues
						]				
					}
				} else {
					compare(original.eGet(feature), revised.eGet(feature), feature, onMatched)
				}
				
				if (!valueDeltas.empty || !matches.empty) {
					val settingDelta = factory.createDSetting
					settingDelta.featureID = eClass.getFeatureID(feature)
					settingDelta.deltas += valueDeltas
					settingDelta.matches += matches	
					settingDeltas += settingDelta
				}
			}
		}
		
		if (!settingDeltas.empty) {
			val objectDelta = factory.createDObject
			objectDelta.originalClass = eClass
			objectDelta.settings += settingDeltas
			return objectDelta
		} else {
			return null	
		}
	}
	
	protected def EObject copy(EObject eObject) {
		return copier.copy(eObject)
	}
	
	protected def boolean equals(EObject original, EObject revised) {
		return EcoreUtil.equals(original, revised)
	}
	 
	protected def MatchType match(EObject original, EObject revised) {
		val nameFeature = original.eClass.getEStructuralFeature("name")
		if (nameFeature != null) {
			val originalName = original.eGet(nameFeature)
			val revisedName = revised.eGet(nameFeature)
			if (originalName != null && revisedName != null) {
				if (originalName.equals(revisedName)) {
					return MatchType.match
				}
			}
		}
		if (equals(original, revised)) {
			return MatchType.equal
		} else {
			return MatchType.different 
		}
	}
	
	private def boolean compare(Object original, Object revised, EStructuralFeature feature, (EObject,EObject)=>void onMatch) {
		return if (original == null || revised == null) {
			original == revised
		} else if (original == revised) {
			true
		} else {	
			switch feature {
				EAttribute: {
					if (original.equals(revised)) {
						true
					} else {
						false
					}	
				}
				EReference: {
					val pair = (original as EObject)->(revised as EObject)
					val existingMatch = matches.get(pair)
					if (existingMatch == null) {
						val newMatch = match(original as EObject, revised as EObject)
						if (newMatch == MatchType.match && feature.containment) {
							onMatch.apply(original as EObject, revised as EObject)
						} 
						matches.put(pair,newMatch)												
						newMatch != MatchType.different
					} else {						
						existingMatch != MatchType.different
					}
				}
				default: unreachable as Boolean
			}			
		}
	}
	
	private def Object unreachable() {
		throw new RuntimeException("Unreachable")
	}
	
	private def precondition(()=>boolean condition) {
		if (!condition.apply) {
			throw new RuntimeException("Condition failed")
		}
	}
}