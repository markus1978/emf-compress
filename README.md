# Synopsis

EMF-Compress is a framework that allows to delta compress similar EMF-models.
A set of similar models is represented as a sequence of model revisions, where only the first 
revision is persisted element-by-element and the others are persisted as sets of differences to 
previous revisions. EMF-Compress comprises a delta-meta-model that describes the means to express 
matches and differences between revisions; a compare algorithm that can derive a delta-model from 
a given original and revised model; and finally a patch algorithm that can re-construct the 
revised model an original model and a delta-model. Clients can provide different 
compare-configurations that either yield better compression or better runtime performance. 

# How does comparison work?

Diff-algorithms that can find the *minimum editing distance*, i.e. a minimum set of changes, between
two sequences have been used for a long time in comparing files byte by byte or line by line.
But models are not sequences but trees (containment hierarchy) of model-elements. Therefore,
regular diff-algorithms have to be applied multiple times starting at the top of the containment
hierarchy going down towards the leaves. Differences can be found at all levels and consequently
form themselves hierarchies. 

Furthermore, high-up the containment hierarchy, we cannot determine
if two elements are the same or not. Instead, we match two elements based on heuristics. For example,
if two model elements have the same name, or signature, or exibit similar structure, we
simply assume that they are meant to be the same, i.e. we say they match each other.
Matching elements are then compared feature by feature. Regular diff-algorithms are applied on 
the value-sets of each feature, matching or not-matching their values and comparing recursively down the hierarchy. 
At lower levels in the containment hierarchy, we might abandon matching and diff-algorithms altogether and simply compare
elements for equality. This is reasonable if matching is expensive compared to the sizes of the
left containment hierarchies, i.e. the compression potential is low compared to the runtime cost of finding the differences.

# What about EMF-Compare and others?

Other framework use a similar strategy to compare models, but follow different goals.
[EMF-Compare](https://www.eclipse.org/emf/compare/) and other model compare/diff frameworks are tailored to show matches and 
differences in individual models to humans. In this scenario, runtime performance is of minor 
importance and is trumped by the quality of the compare. The used algorithms try to identify the 
*minimum editing distance* between two models applying complicated heuristics to match model elements
all the way down the containment hierarchy. 

Compression requires to compare lots and lots of models in a short amount of time. In this scenario, 
runtime-performance and quality of comparison have to be weighed against each other. EMF-Compare
allows clients to provide simple match strategies based on their meta-models and allows clients
to configure the depth until matching is used and before elements are just compared for equality.
Therefore, EMF-Compress identifies a *small editing distance*, but not necessarily the smallest and
thus yields both reasonable compression and reasonable runtime performance.

# The match-delta model

While other frameworks strictly separate matching and finding differences; represent matches
and differences in separate models, EMF-compress does both in one step and represents both in 
a singular delta-model. This is bad to present matches and differences to human users, but it
is sufficient to patch models and yields good runtime performance and small delta-models.

![meta-model](https://github.com/markus1978/emf-compress/blob/master/plugins/de.hub.emfcompress/models/compress.png)

Furthermore, the delta-model is not symmetrical. It treats the compared original and revised 
models differently. The delta-model represents changes to the original model. All changes to an original
model element are represented within an instance of **ObjectDelta**. **SettingDelta** and **ValuesDelta** instances are
used to represent changes to respective features and value-sets (aka settings). Feature values are generalized as
lists and deltas to these list (**ValuesDelta**) are represented by replacing values in the original list (refered to by indices in the original list) with 
values of the revised list (refered to by reference). 

Revised values are references different depending on their nature (data values, cross references model elements, or contained model elements).
Revised values are part of the delta-model. These are either copies from the actual revised model, or they are references to the
matching elements from the original model which are represented by **ObjectDetla** instances in the delta-model.

**ObjectDeltas** can contain other **ObjectDeltas** to form hierarchies of deltas. Each **ObjectDelta** represents
a changed element from the original model. If the contents of an original model elements matches contents
of its matching revised model element, this match and all changes to the matched elements are also represented by an
**ObjectDelta**. The **ObjectDeltas** that represent matching values with respect to a certain feature of
the containing element are contained in the **SettingDetla** that represents this feature of the containing model element delta.
To identify an **ObjectDelta** within the list of values in a setting the index of the original element within that setting is used.

# Patching

Given a delta-model and an original, patching is very straight forward. The deltas are directly 
translated into changes to the original.

# Using EMF-Compress

Tutorial, interface description, and examples are comming soon. Refer to the provided unit tests for now.

Copyright 2016 Markus Scheidgen
