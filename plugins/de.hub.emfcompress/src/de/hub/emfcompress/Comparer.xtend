package de.hub.emfcompress

import de.hub.emfcompress.internal.EmfCompressModel
import difflib.DiffUtils
import java.util.Collection
import java.util.List
import java.util.Map
import org.eclipse.emf.ecore.EAttribute
import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EReference
import org.eclipse.emf.ecore.EStructuralFeature
import org.eclipse.emf.ecore.util.EcoreUtil
import org.eclipse.emf.ecore.util.EcoreUtil.Copier

/**
 * A comparer can be used to compare to objects (and everything they contain). The comparison produces a 
 * delta that can be used to patch one object (original) to yield the other object (revised).
 * The patches in fully independent of the original and revised and holds no direct EMF references
 * to either of the models. Elements of the original model are referred to by means of features and indices;
 * elements to the revised model are copied to be part of the patch.
 * 
 * Comparer can be configured through the protected callback methods.
 */
class Comparer {
	
	var extension EmfCompressModel model = null
	
	val EmfCompressFactory factory
	val extension ComparerConfiguration config 
	
	val Collection<EObject> noMatchesOrEquals = newHashSet
	val Map<EObject, EObject> matchesAndEquals = newHashMap
	
	/**
	 * A special EcoreUtils.Copier that deals with references that have targets outside 
	 * the copied object's containment hierarchies.
	 */	
	val copier = new Copier {
		/**
		 * A specialization of the inherited get method. It provides proxys for referenced
		 * objects that are outside the containment hierarchies of copied elements.
		 */
		override get(Object key) {
			val result = super.get(key)
			if (result == null) {
				// a reference is requested that was not copied
				val revised = key as EObject
				val original = matchesAndEquals.get(revised)
				val delta = original.objectDelta
				var proxy = delta.originalProxy
				if (proxy == null) {
					val proxyClass = getTarget(revised.eClass)
					proxy = proxyClass.EPackage.EFactoryInstance.create(proxyClass)
					delta.originalProxy = proxy
				}		
				return proxy				
			} else {
				return result
			}
		}		
	}
	
	/**
	 * A special EcoreUtil.EqualityHelper that refers the comparison of cross references
	 * back to the comparer. This is necessary, because the original EqualityHelper 
	 * implementation only works for references that keep within the compared objects 
	 * containment hierarchies.
	 */
	val equalityHelper = new EcoreUtil.EqualityHelper {
		override protected haveEqualReference(EObject eObject1, EObject eObject2, EReference reference) {
			val value1 = eObject1.eGet(reference);
	  		val value2 = eObject2.eGet(reference);
	
			return if (reference.containment) {
				if (reference.many) {
					super.equals(value1 as List<EObject>, value2 as List<EObject>)
				} else {
					super.equals(value1 as EObject, value2 as EObject)
				}
			} else {
		  		if (reference.many) {
					val list1 = value1 as List<EObject>
					val list2 = value2 as List<EObject>
					val size = list1.size();
					if (size != list2.size()) {
						false
					} else {
						for (i : 0 ..< size) {
							if (!Comparer.this.equals(list1.get(i), list2.get(i))) {
								return false
							}
						}
						true
					}
				} else {
					Comparer.this.equals(value1 as EObject, value2 as EObject)
				}
			}
		}
	}

	val List<Pair<ReferencedObjectsDelta, List<EObject>>> references = newArrayList
	
	new(ComparerConfiguration config, EmfCompressFactory factory) {
		this.factory = factory
		this.config = config
	}
	
	new(ComparerConfiguration config) {
		this.factory = EmfCompressFactory.eINSTANCE
		this.config = config
	}
	
	private def void reset() {
		noMatchesOrEquals.clear
		matchesAndEquals.clear
		copier.clear
		references.clear
	}
	
	/**
	 * Compares the given elements and produces a delta that can be used to
	 * patch the first object (original) to yield the second object (revised).
	 */
	public def ObjectDelta compare(EObject original, EObject revised) {
		reset
		model = new EmfCompressModel(factory, original)
		
		// Add all matches recursively to the delta model
		match(original, revised)
		// Add all differences recursively to the delta model
		diff(original, revised)
				
		// References to elements of the original model (created in the previous step)
		// have been and are now added/replaced as/with ObjectDeltas and corresponding
		// proxies.
		handleReferences
	
		return model.rootDelta		
	}
	
	public def boolean match(EObject original, EObject revised) {
		if (original.eClass != revised.eClass) {
			return false	
		}
		
		val result = if (config.match(original, revised)) {
			matchesAndEquals.put(original, revised)
			matchesAndEquals.put(revised, original)	
			val eClass = original.eClass
			val matchReferences = eClass.EAllReferences.filter[containment &&
				changeable && !derived && !ignore && compareWithMatch(eClass, it) && !derivedFromOpposite 
			]
			for (matchReference:matchReferences) {
				val List<EObject> originalValues = original.eGetList(matchReference)
				val List<EObject> revisedValues = revised.eGetList(matchReference)
				val patch = DiffUtils.diff(originalValues, revisedValues) [comparedOriginal,comparedRevised|
					match(comparedOriginal,comparedRevised) 
				]
				patch.deltas.forEach[
					val replacedObjectValues = factory.createContainedObjectsDelta
					it.revised.lines.forEach[
						replacedObjectValues.revisedObjectContainments += it.containment
					]
					replacedObjectValues.originalStart = it.original.position
					replacedObjectValues.originalEnd = it.original.position + it.original.size
					original.settingDelta(matchReference).valueDeltas += replacedObjectValues
				]				
			}	
			true	
		} else {
			noMatchesOrEquals.add(original)
			false
		}
		
		result
	}
	
	public def void diff(EObject original, EObject revised) {
		val eClass = original.eClass
		val diffFeatures = eClass.EAllStructuralFeatures.filter[changeable && !derived && !ignore && !derivedFromOpposite]
		for(diffFeature:diffFeatures) {
			val isMatchFeature = if (diffFeature instanceof EReference) {
				diffFeature.containment && compareWithMatch(eClass, diffFeature)
			} else {
				false
			}
			if (isMatchFeature) {
				val List<EObject> orginalValues = original.eGetList(diffFeature)
				for(originalValue:orginalValues) {
					val matchingValue = matchesAndEquals.get(originalValue)
					if (matchingValue != null) {
						diff(originalValue, matchingValue)
					}
				}				
			} else {	
				val originalValues = original.eGetList(diffFeature)
				val revisedValues = revised.eGetList(diffFeature)
				val (Object,Object)=>boolean compare = switch (diffFeature) {
					EAttribute: [comparedOriginal, comparedRevised| comparedOriginal == comparedRevised || (comparedOriginal != null && comparedOriginal.equals(comparedRevised))]
					EReference: [comparedOriginal, comparedRevised|
						equals(comparedOriginal as EObject, comparedRevised as EObject)
					]
				}
				val patch = DiffUtils.diff(originalValues, revisedValues, compare)
				if (!patch.deltas.empty) {
					val settingDelta = settingDelta(original, diffFeature)
					patch.deltas.forEach[
						val replacedValues = switch diffFeature {
							EAttribute: {
								val replacedDataValues = factory.createDataValuesDelta
								it.revised.lines.forEach[replacedDataValues.revisedValues += it]
								replacedDataValues							
							}
							EReference: {
								if (diffFeature.containment) {
									val replacedObjectValues = factory.createContainedObjectsDelta
									it.revised.lines.forEach[
										replacedObjectValues.revisedObjectContainments += (it as EObject).containment
									]
									replacedObjectValues									
								} else {
									val replacedObjectValues = factory.createReferencedObjectsDelta
									val referencedValues = newArrayList
									it.revised.lines.forEach[
										referencedValues.add(it as EObject)
									]
									references.add(replacedObjectValues->referencedValues)
									replacedObjectValues
								}
							}
							default: unreachable as ValuesDelta
						}
						
						replacedValues.originalStart = it.original.position
						replacedValues.originalEnd = it.original.position + it.original.size
						settingDelta.valueDeltas += replacedValues				
					]				
				}				
			}
		}
	}
	
	private def <T> List<T> eGetList(EObject container, EStructuralFeature feature) {
		return if (feature.many) {
			container.eGet(feature) as List<T>
		} else {
			val value = container.eGet(feature) as T
			if (value == null) #[] else #[container.eGet(feature) as T]	
		}
	}
	
	private def void handleReferences() {
		for(referenceDelta:references) {
			val delta = referenceDelta.key
			val values = referenceDelta.value
			for(value:values) {
				val copy = copier.get(value)
				val reference = if (copy != null) {
					val newReference = factory.createRevisedObjectReference
					newReference.revisedObject = copy
					newReference
				} else {
					val equalOriginal = matchesAndEquals.get(value)
					if (equalOriginal != null) {
						val newReference = factory.createOriginalObjectReference
						newReference.originalObject = equalOriginal.objectDelta
						newReference
					} else {
						unreachable as ObjectReference
					}
				}
				delta.revisedObjectReferences.add(reference)
			}
		}
		
		// handle references in copier, the copier's specialized get 
		// method will create proxies for non copied elements
		copier.copyReferences	
	}
	
   /**
	 * For a pair of opposing references, only one should be used during comparison.
	 * @returns true, if the given feature is already used during comparison.
	 */
	private def boolean derivedFromOpposite(EStructuralFeature feature) {
		switch(feature) {
			EAttribute: return false
			EReference: 
				if (feature.containment) {
					return false
				} else {
					return if (feature.EOpposite != null) {
						val opposite = feature.EOpposite
						val result = if (!opposite.changeable || opposite.derived) {
							false
						} else if (opposite.containment) {
							true
						} else if (!feature.many && opposite.many) {
							false // prefer the single valued feature
						} else if (feature.many && !opposite.many) {
							true
						} else {
							// use a unique but meaningless criteria
							val featureHC = System.identityHashCode(feature)
							val oppositeHC = System.identityHashCode(opposite)
							if (featureHC == oppositeHC) { // extremely unlikely 
								unreachable as Boolean // TODO compare by qualified name
							} else {
								featureHC > oppositeHC
							}
						}			
						
						return result		
					} else {
						false
					}					
				}
			default: return unreachable as Boolean
		}		
	}
	
	private def containment(EObject revisedObject) {
		val matchingOriginalObject = matchesAndEquals.get(revisedObject)
		return if (matchingOriginalObject == null) {
			val revisedContainment = factory.createRevisedObjectContainment
			revisedContainment.revisedObject = copier.copy(revisedObject)
			revisedContainment
		} else {
			val originalContainment = factory.createOriginalObjectContainment
			originalContainment.originalObject = matchingOriginalObject.objectDelta
			originalContainment
		}
	}
	
	private def boolean equals(EObject original, EObject revised) {
		switch compareBase(original, revised) {
			case 1: return true
			case -1: return false
		}
		
		matchesAndEquals.put(original, revised)
		val areEqual = haveEqualContext(original, revised) && haveEqualContents(original, revised)
		if (!areEqual) {
			noMatchesOrEquals += original
			matchesAndEquals.remove(original)
		} else {
			matchesAndEquals.put(revised, original)
		}
		
		return areEqual
	}
	
	private def int compareBase(EObject original, EObject revised) {
		if (original == null || revised == null) {
			return if (original == revised) 1 else -1
		} 
		if (original.eClass != revised.eClass) {
			return -1
		} 
		if (noMatchesOrEquals.contains(original)) {
			return -1
		} 
					
		val match = matchesAndEquals.get(original)
		if (match != null) {
			return if (match == revised) 1 else -1
		}
	
		return 0
	}
	
	private def boolean haveEqualContents(EObject original, EObject revised) {
		equalityHelper.clear		
		val result = equalityHelper.equals(original, revised)
		if (result) {
			matchesAndEquals.putAll(equalityHelper)
		}
		return result
	}
	
	private def boolean haveEqualContext(EObject original, EObject revised) {
		if (original.eContainmentFeature == revised.eContainmentFeature) {
			val containmentFeature = original.eContainingFeature
			val originalContainer = original.eContainer
			val revisedContainer = revised.eContainer
			
			if (containmentFeature.many) {
				val originalIndex = (originalContainer.eGet(containmentFeature) as List<EObject>).indexOf(original)
				val revisedIndex = (revisedContainer.eGet(containmentFeature) as List<EObject>).indexOf(revised)
				if (originalIndex != revisedIndex) {
					return false
				}
			}
			
			return equals(originalContainer, revisedContainer)				
		} else {
			return false
		}	
	}
	
	private def <T> T unreachable() {
		throw new RuntimeException("Unreachable")
	}
}
