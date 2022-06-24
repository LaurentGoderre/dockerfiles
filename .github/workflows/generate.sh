#!/usr/bin/env bash
set -Eeuo pipefail

bashbrewDir="$1"

export BASHBREW_NAMESPACE='tianon'

strategy='{}'
for gsl in */gsl.sh; do
	dir="$(dirname "$gsl")"
	img="$(basename "$dir")"
	img="$BASHBREW_NAMESPACE/$img"
	newStrategy="$(GENERATE_STACKBREW_LIBRARY="$gsl" GITHUB_REPOSITORY="$img" "$bashbrewDir/scripts/github-actions/generate.sh")"
	if [ "$img" = 'tianon/cygwin' ]; then
		# remove tags that Windows on GitHub Actions can't test
		newStrategy="$(jq -c 'del(.matrix.include[] | select(.os == "invalid-or-unknown"))' <<<"$newStrategy")"
	fi
	newStrategy="$(jq -c --arg img "$img" '.matrix.include = [ .matrix.include[] | .name = $img + ": " + .name ]' <<<"$newStrategy")"
	jq -c . <<<"$newStrategy" > /dev/null # sanity check
	strategy="$(jq -c --argjson strategy "$strategy" '.matrix.include = ($strategy.matrix.include // []) + .matrix.include' <<<"$newStrategy")"
done
jq -c . <<<"$strategy" > /dev/null # sanity check

# now that we have a list of legit images with generate scripts, look for dangling Dockerfiles
allDockerfiles="$(git ls-files '*/Dockerfile' | jq -Rsc 'rtrimstr("\n") | split("\n")')"
danglingDockerfiles="$(jq <<<"$strategy" -c --argjson allDockerfiles "$allDockerfiles" '$allDockerfiles - [ .matrix.include[].meta.dockerfiles[] ]')"

# TODO this could probably be implemented via some crafted "GENERATE_STACKBREW_LIBRARY" expressions that output a fake GSL file 🤔
strategy="$(jq -c --argjson danglingDockerfiles "$danglingDockerfiles" '.matrix.include[0] as $first | .matrix.include += [
	$danglingDockerfiles[]
	| sub("/Dockerfile$"; "") as $dir
	| (env.BASHBREW_NAMESPACE + "/" + ($dir | sub("/"; ":") | gsub("/"; "-"))) as $img
	| {
			name: ("DANGLING: " + . + " (" + $img + ")"),
			os: "ubuntu-latest",
			runs: {
				prepare: $first.runs.prepare,
				build: ("docker build -t " + ($img | @sh) + " " + ($dir | @sh)),
				history: ("docker history " + ($img | @sh)),
				test: ("~/oi/test/run.sh --config ~/oi/test/config.sh --config .test/config.sh " + ($img | @sh)),
				images: $first.runs.images,
			},
	}
]' <<<"$strategy")"

if [ -t 1 ]; then
	jq <<<"$strategy"
else
	cat <<<"$strategy"
fi
