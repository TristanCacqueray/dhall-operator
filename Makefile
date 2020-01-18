lint:
	@bash -c 'for f in $$(find . -name "*.dhall"); do dhall format --ascii < $$f > $$f.fmt; mv $$f.fmt $$f; done'
