import { expect, test } from "vitest";
import { buildPublicRoutes, normalizePublicRoute } from "./public-routes.ts";

test("keeps identity separate from canonical and historical routes", () => {
	expect(
		buildPublicRoutes([
			{
				path: "notes/old.md",
				original: "/notes/old/",
				permalink: "/journal/new",
				aliases: ["/archive/old", "/first-name/"],
			},
		]),
	).toEqual([
		{
			path: "notes/old.md",
			original: "/notes/old",
			canonical: "/journal/new",
			redirects: ["/notes/old", "/archive/old", "/first-name"],
		},
	]);
	expect(normalizePublicRoute("/")).toBe("/");
	expect(
		buildPublicRoutes([
			{
				path: "welcome.md",
				original: "/welcome",
				permalink: "/",
			},
		])[0],
	).toMatchObject({ canonical: "/", redirects: ["/welcome"] });
});

test("rejects collisions, loops, and duplicate redirects", () => {
	expect(() =>
		buildPublicRoutes([
			{ path: "a.md", original: "/a", permalink: "/shared" },
			{ path: "b.md", original: "/b", aliases: ["/shared"] },
		]),
	).toThrow(/collision.*shared/i);
	expect(() =>
		buildPublicRoutes([{ path: "a.md", original: "/a", aliases: ["/a"] }]),
	).toThrow(/loop/i);
	expect(() =>
		buildPublicRoutes([
			{ path: "a.md", original: "/a", aliases: ["/old", "/old/"] },
		]),
	).toThrow(/duplicate redirect/i);
	expect(() =>
		buildPublicRoutes([{ path: "a.md", original: "/a", aliases: ["old-a"] }]),
	).toThrow(/full path/i);
});
