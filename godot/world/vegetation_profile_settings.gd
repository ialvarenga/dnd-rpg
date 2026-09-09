class_name VegetationProfileSettings
extends Resource

## Data-only tuning for the deterministic scatter generator, mirroring
## TerrainProfileSettings. Every field is an environment knob: what grows here,
## how big it gets, how tightly it packs, and how patchy the stand is.

## Relative share of each family. Values are normalised, so they need not sum
## to one; families absent from the catalog are dropped before the roll.
@export var family_weights := {"tree": 0.30, "bush": 0.25, "grass": 0.37, "rock": 0.08}

## Reverse-J (de Liocourt) shape parameter for picking a model within a family:
## w(a) = exp(-size_lambda * radius(a) / largest_radius_in_family).
## Positive means many small stems and few giants, the shape of a naturally
## regenerating stand. Negative inverts it into old growth: sparse and large.
@export_range(-4.0, 6.0, 0.1) var size_lambda := 1.8

## Fraction of a model's canopy radius that neighbours may interpenetrate.
## Zero packs to touching canopies; higher values interlock into closed forest.
@export_range(0.0, 0.9, 0.05) var canopy_overlap := 0.25

## Spacing floor in metres, so 14cm grass tufts cannot generate by the thousand.
@export_range(0.2, 8.0, 0.1) var min_spacing_m := 0.8

## fBm field driving local density. Lower frequency means larger groves and
## clearings; contrast is the exponent applied to the field, so higher values
## push the stand towards all-or-nothing patches.
@export_range(0.005, 0.2, 0.005) var density_noise_frequency := 0.035
@export_range(0.2, 6.0, 0.1) var density_contrast := 1.6

## Thomas cluster process for undergrowth: grass and bushes grow in clumps
## around a parent rather than as blue noise. Trees and rocks stay unclustered.
@export_range(0, 8, 1) var cluster_children := 3
@export_range(0.2, 6.0, 0.1) var cluster_sigma_m := 1.4

## Hard per-region instance cap. Every placement is still its own scene node,
## so this is the backstop until the generator feeds a MultiMesh.
@export_range(0, 4000, 10) var max_instances := 900
