# ArchivesSpace-EAD-Update

The ULS updated ArchivesSpace records via SQL to deduplicate container ids recorded there.  As a result, we need to reload each modified Finding Aid within our legacy Islandora 7 instance.

This code takes in a list of affected ASpace records, downloads all Finding Aids from Islandora 7, searches for the EAD identifier in the downloaded files, downloads the matched EAD by EAD ID from ASpace, and then uploads the changed EADs back to Islandora 7.
