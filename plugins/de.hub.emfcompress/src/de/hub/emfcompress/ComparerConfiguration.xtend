package de.hub.emfcompress

import org.eclipse.emf.ecore.EObject
import org.eclipse.emf.ecore.EStructuralFeature

interface ComparerConfiguration {
	/**
	 * Callback that allows clients to determine if a feature should be ignored 
	 * during comparison.
	 * @returns true, if the feature is to be ignored.
	 */	
	def boolean ignore(EStructuralFeature feature)
	
	/**
	 * Callback that allows clients to determine if the given objects should be 
	 * compared to match or should be compared to equal.
	 * @returns true, if the given objects should be matched and not equaled.
	 */
	def boolean compareWithMatch(EObject original,EObject revised)
	
	/**
	 * Callback that allows clients to provide custom match rules. 
	 * @returns true, if the given objects match.
	 */
	def boolean match(EObject original,EObject revised) 
}