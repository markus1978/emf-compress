package de.hub.emfcompress.internal

import de.hub.emfcompress.ObjectDelta
import de.hub.emfcompress.SettingDelta
import java.util.List
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature
import java.util.Map
import de.hub.emfcompress.EmfCompressFactory

class EmfCompressModel {
	val EmfCompressFactory factory
	val EObject rootOriginal
	val ObjectDelta rootDelta 
	val Map<EObject,ObjectDelta> objectDeltas = newHashMap
	val Map<ObjectDelta, EObject> originalObjects = newHashMap
	
	new(EmfCompressFactory factory, EObject rootOriginal) {
		this.factory = factory
		this.rootOriginal = rootOriginal
		this.rootDelta = rootOriginal.objectDelta
	}
	
	public def SettingDelta existingSettingDelta(EObject original, EStructuralFeature feature) {
		val objectDelta = original.existingObjectDelta
		if (objectDelta != null) {
			val featureID = objectDelta.originalClass.getFeatureID(feature)
			return objectDelta.settingDeltas.findFirst[it.featureID == featureID]
		} else {
			return null
		}
	}
	
	public def ObjectDelta existingObjectDelta(EObject original) {
		return objectDeltas.get(original)
	}
	
	public def getRootDelta() {
		return rootDelta
	}
	
	public def getRootOriginal() {
		return rootOriginal
	}
	
	/**
	 * Transforms a given original and feature into a SettingDelta, if it
	 * does not already exist. Used for lazy delta construction.	  
	 */
	public def SettingDelta settingDelta(EObject original, EStructuralFeature feature) {
		val existing = existingSettingDelta(original, feature)
		if (existing == null) {
			val containerDelta = original.objectDelta
			val featureID = original.eClass.getFeatureID(feature)			
			val newSettingDelta = factory.createSettingDelta
			newSettingDelta.featureID = featureID
			containerDelta.settingDeltas.add(newSettingDelta)
			return newSettingDelta
		} else {
			return existing
		}		
	}
	
	/**
	 * Transforms a given original into a ObjectDelta, if it
	 * does not already exist. Used for lazy delta construction.	  
	 */
	public def ObjectDelta objectDelta(EObject original) {		
		val existingDelta = original.existingObjectDelta
		
		if (existingDelta == null) {			
			val newDelta = factory.createObjectDelta
			newDelta.originalClass = original.eClass
			objectDeltas.put(original, newDelta)
			originalObjects.put(newDelta, original)
			
			val containmentFeature = original.eContainmentFeature
			if (containmentFeature != null) {
				val container = original.eContainer
				if (containmentFeature.many) {				
					newDelta.originalIndex = (container.eGet(original.eContainmentFeature) as List<Object>).indexOf(original)			
				}
				container.settingDelta(containmentFeature).matchedObjects.add(newDelta)			
			}		
			return newDelta
		} else {
			return existingDelta
		}
	}
	
	public def EObject originalObject(ObjectDelta delta) {
		originalObjects.get(delta)
	}
}