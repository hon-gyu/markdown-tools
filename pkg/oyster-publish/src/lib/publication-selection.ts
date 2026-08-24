export interface PublicationRules {
	includeFolders: string[];
	excludeFolders: string[];
	linkedNotes: boolean;
}

export const defaultPublicationRules: PublicationRules = {
	includeFolders: [],
	excludeFolders: [],
	linkedNotes: false,
};

const normalizeFolder = (folder: string) => folder.replace(/^\/+|\/+$/g, "");
const inside = (path: string, folder: string) => {
	const prefix = normalizeFolder(folder);
	return prefix === "" || path === prefix || path.startsWith(`${prefix}/`);
};

export function initiallyPublished(
	path: string,
	publish: boolean | undefined,
	rules: PublicationRules,
	publishedOnly: boolean,
): boolean {
	if (publish === false) return false;
	if (publishedOnly) return publish === true;
	if (publish === true) return true;
	if (rules.excludeFolders.some((folder) => inside(path, folder))) return false;
	if (rules.includeFolders.length > 0) {
		return rules.includeFolders.some((folder) => inside(path, folder));
	}
	return true;
}
