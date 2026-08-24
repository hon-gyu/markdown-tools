import { BreadcrumbItem, Breadcrumbs } from "@astryxdesign/core/Breadcrumbs";
import { Theme } from "@astryxdesign/core/theme";
import { neutralTheme } from "@astryxdesign/theme-neutral";

export interface OysterBreadcrumb {
	label: string;
	href?: string;
	current?: boolean;
}

export default function OysterBreadcrumbs({
	items,
}: {
	items: OysterBreadcrumb[];
}) {
	if (items.length < 2) return null;
	return (
		<Theme theme={neutralTheme}>
			<Breadcrumbs variant="supporting" label="Page path">
				{items.map((item) => (
					<BreadcrumbItem
						key={item.href ?? item.label}
						href={item.href}
						isCurrent={item.current}
					>
						{item.label}
					</BreadcrumbItem>
				))}
			</Breadcrumbs>
		</Theme>
	);
}
