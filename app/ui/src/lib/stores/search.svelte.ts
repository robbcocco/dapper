/** Sidebar search query (searchQueryProvider) and the search box element (searchFocusProvider). */
export const search = $state<{ query: string; input: HTMLInputElement | null }>({ query: '', input: null });

export function focusSearch(): void {
  search.input?.focus();
  search.input?.select();
}
