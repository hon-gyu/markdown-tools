export interface PublicRouteInput {
	path: string;
	original: string;
	permalink?: string;
	aliases?: string[];
}

export interface PublicRoute {
	path: string;
	canonical: string;
	original: string;
	redirects: string[];
}

export function normalizePublicRoute(value: string): string {
	const route = `/${value.trim().replace(/^\/+|\/+$/g, "")}`;
	return route === "/" ? route : route.replace(/\/{2,}/g, "/");
}

export function buildPublicRoutes(inputs: PublicRouteInput[]): PublicRoute[] {
	const routes = inputs.map((input) => {
		if (input.permalink && !input.permalink.startsWith("/")) {
			throw new Error(
				`Permalink must be a full path for ${input.path}: ${input.permalink}`,
			);
		}
		const relativeAlias = (input.aliases ?? []).find(
			(alias) => !alias.startsWith("/"),
		);
		if (relativeAlias) {
			throw new Error(
				`Alias must be a full path for ${input.path}: ${relativeAlias}`,
			);
		}
		const original = normalizePublicRoute(input.original);
		const canonical = input.permalink
			? normalizePublicRoute(input.permalink)
			: original;
		const redirects = [
			...(canonical !== original ? [original] : []),
			...(input.aliases ?? []).map(normalizePublicRoute),
		];
		if (redirects.includes(canonical)) {
			throw new Error(`Redirect loop for ${input.path}: ${canonical}`);
		}
		if (new Set(redirects).size !== redirects.length) {
			throw new Error(`Duplicate redirect for ${input.path}`);
		}
		return { path: input.path, original, canonical, redirects };
	});

	const owners = new Map<string, string>();
	for (const route of routes) {
		for (const candidate of [route.canonical, ...route.redirects]) {
			const owner = owners.get(candidate);
			if (owner && owner !== route.path) {
				throw new Error(
					`Public route collision at ${candidate}: ${owner} and ${route.path}`,
				);
			}
			owners.set(candidate, route.path);
		}
	}
	return routes;
}
