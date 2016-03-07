Synopsis
--------

This frameworks allows to delta compress similar EMF models. 
It provides a model for expressing the differences between two models.
It provides capabilities to compare two models. It creates a difference model from an original and revised model.
Different to emf-compare and similar frameworks, emf-compress allows to configure matching and how deep two models are to be compared. 
In stead of concentrating fully on minimum editing distance, our comparision can be tailored torwards perfomance while sacrifycing compression.
Furthermore, matches and differences are encoding into a single delta model. The delta meta-model is tailored torwards efficient persistence. 
Of course the framework offers patching capabilities to reconstruct the revised model from an original and a delta model.
Finally, a single original and multiple delta models representing consecutive revision models can be used as a compressed representation of multiple revisions for the same original model.

Copyright 2016 Markus Scheidgen
