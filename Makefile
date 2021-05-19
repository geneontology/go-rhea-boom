# Need on path: boomer & robot

all: rhea-boom.txt

rhea2%.tsv:
	curl -L -O ftp://ftp.expasy.org/databases/rhea/tsv/rhea2$*.tsv
.PRECIOUS: rhea2%.tsv

# Prefer subclass for Reactome
rhea-reactome-probs.tsv: rhea2reactome.tsv
	tail -n +2 $< | cut -f 1,4 | sed '/^$$/d' | sed 's/^/RHEA:/' | sed 's/	/	REACTOME:/' | sed 's/$$/	0.10	0.70	0.15	0.05/' >$@ #$*

# Prefer equivalent class for most mappings
rhea-%-probs.tsv: rhea2%.tsv
	tail -n +2 $< | cut -f 1,4 | sed '/^$$/d' | sed 's/^/RHEA:/' | sed 's/	/	$(shell echo $* | tr [:lower:] [:upper:]):/' | sed 's/$$/	0.10	0.10	0.75	0.05/' >$@
.PRECIOUS: rhea-%-probs.tsv

rhea-relationships.tsv:
	curl -L -O ftp://ftp.expasy.org/databases/rhea/tsv/rhea-relationships.tsv

rhea-relationships.ofn: rhea-relationships.tsv
	tail -n +2 $< | sed 's/^/SubClassOf(RHEA:/' | sed 's/	is_a	/ RHEA:/' | sed 's/$$/)/' >$@

rhea-directions.tsv:
	curl -L -O https://ftp.expasy.org/databases/rhea/tsv/rhea-directions.tsv

rhea-equivalents.ofn: rhea-directions.tsv
	tail -n +2 $< | sed 's/^/EquivalentClasses(RHEA:/' | sed 's/	/ RHEA:/g' | sed 's/$$/)/' >$@

rhea.ofn: rhea-relationships.ofn rhea-equivalents.ofn
	cp rhea-relationships-head.txt $@.tmp &&\
	cat rhea-relationships.ofn >>$@.tmp &&\
	cat rhea-equivalents.ofn >>$@.tmp &&\
	echo ')' >> $@.tmp && mv $@.tmp $@

enzyme.rdf:
	curl -L -O https://ftp.expasy.org/databases/enzyme/enzyme.rdf

go-plus.owl:
	curl -L -O http://purl.obolibrary.org/obo/go/snapshot/extensions/go-plus.owl

go-ec-rhea-metacyc-xrefs.tsv: go-plus.owl xrefs.rq
	robot query -i $< -f TSV -q xrefs.rq $@.tmp &&\
	tail -n +2 $@.tmp | sed 's/^<http:\/\/purl.obolibrary.org\/obo\/GO_/GO:/' | sed 's/>//' | sed 's/"//g' | sort -u >$@.tmp2 &&\
	rm $@.tmp && mv $@.tmp2 $@

# These files must be sorted!
go-ec-rhea-metacyc-xrefs-filtered.tsv: go-ec-rhea-metacyc-xrefs.tsv questionable-GO-Rhea.tsv
	comm -23 go-ec-rhea-metacyc-xrefs.tsv questionable-GO-Rhea.tsv >$@

# These files must be sorted!
go-exact-xrefs-probs-questionable.tsv: go-ec-rhea-metacyc-xrefs.tsv questionable-GO-Rhea.tsv
	comm -12 go-ec-rhea-metacyc-xrefs.tsv questionable-GO-Rhea.tsv | cut -f1 -f2 | sed 's/$$/	0.15	0.15	0.60	0.10/' >$@

go-exact-xrefs-probs.tsv: go-ec-rhea-metacyc-xrefs-filtered.tsv
	grep -v "skos:" $< | cut -f1 -f2 | sed 's/$$/	0.08	0.08	0.80	0.04/' >$@

go-narrow-xrefs-probs.tsv: go-ec-rhea-metacyc-xrefs-filtered.tsv
	grep "skos:narrowMatch" $< | cut -f1 -f2 | sed 's/$$/	0.06	0.80	0.10	0.04/' >$@

go-broad-xrefs-probs.tsv: go-ec-rhea-metacyc-xrefs-filtered.tsv
	grep "skos:broadMatch" $< | cut -f1 -f2 | sed 's/$$/	0.80	0.06	0.10	0.04/' >$@

probs.tsv: rhea-ec-probs.tsv rhea-metacyc-probs.tsv rhea-reactome-probs.tsv go-exact-xrefs-probs.tsv go-narrow-xrefs-probs.tsv go-broad-xrefs-probs.tsv go-exact-xrefs-probs-questionable.tsv
	cat $^ >$@

go-rhea.ofn: go-plus.owl rhea.ofn enzyme.rdf
	robot merge -i go-plus.owl -i rhea.ofn -i enzyme.rdf -o $@

rhea-boom: go-rhea.ofn probs.tsv prefixes.yaml
	rm -rf rhea-boom &&\
	boomer --ptable probs.tsv --ontology go-rhea.ofn --window-count 20 --runs 100 --prefixes prefixes.yaml --output rhea-boom --exhaustive-search-limit 14 --restrict-output-to-prefixes=GO --restrict-output-to-prefixes=RHEA

go.obo:
#	curl -L -s http://purl.obolibrary.org/obo/go.obo > $@
	cp ../go-ontology/src/ontology/go-edit.obo $@
.PRECIOUS: go.obo

# inject reactions as synonyms for matching
go-with-reac-syns.obo: go.obo
	obo-grep.pl -r 'def: "Catalysis of the reaction:' $< | perl -npe 's@def: "Catalysis of the reaction: (.*)\." .*@synonym: "$$1" EXACT []@' > $@

go-with-reac-syns.owl.ttl: go-with-reac-syns.obo
	robot convert -i $< -o $@

curated-mappings.sssom.tsv: go-with-reac-syns.obo
	obo-xrefs-to-sssom.pl -p skos:exactMatch $< > $@


# we should probably match over all chebi, start with just the subset used by existing GO axioms
chebi_imports.owl:
	curl -L -s http://purl.obolibrary.org/obo/go/imports/chebi_import.owl > $@

# build up rhea from sparql queries not TSVs, see #1
rhea-%.owl.ttl:
	curl -H "Accept: text/turtle"   --data-urlencode query@sparql/rhea-$*.rq https://sparql.rhea-db.org/sparql > $@

LEXMATCH_INPUT = prefixes.ttl go-with-reac-syns.owl.ttl rhea-core.owl.ttl chebi_imports.owl
defmatches.sssom.tsv: $(LEXMATCH_INPUT)
	rdfmatch $(RDFMATCH_ARGS) --min_weight 4.0 -p GO --match_prefix RHEA $(patsubst %, -i %, $(LEXMATCH_INPUT)) submatch > $@.tmp && mv $@.tmp $@

lexmatches.sssom.tsv: $(LEXMATCH_INPUT)
	rdfmatch $(RDFMATCH_ARGS) --consult conf/rhea_weights.pro -p GO --match_prefix RHEA $(patsubst %, -i %, $(LEXMATCH_INPUT)) match > $@.tmp && mv $@.tmp $@

%-diff.sssom.tsv: %.sssom.tsv curated-mappings.sssom.tsv
	sssom diff $^ -o $@

%-new.sssom.tsv: %-diff.sssom.tsv
	sssom dosql $< -q "SELECT * FROM df WHERE COMMENT='UNIQUE_1' AND match_type='Lexical'" -o $@
