import type { ReactNode } from 'react';

/**
 * Marks a part of a page that a Ziren demo can point at.
 *
 * `display: contents`, so it adds no box and changes no layout (a flex or grid
 * child stays a flex or grid child); the tour measures what is inside it. Not
 * for table rows or cells, where a <div> is not allowed — wrap the table.
 */
export function DemoTarget({ id, children }: { id: string; children: ReactNode }) {
  return (
    <div className="contents" data-demo={id}>
      {children}
    </div>
  );
}
