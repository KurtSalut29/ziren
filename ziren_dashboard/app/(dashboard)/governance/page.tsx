'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

/**
 * Bare /governance always lands on Severity Configuration — for an Agency
 * Admin that page's own logic immediately redirects further, to their one
 * agency's rubric (exactly what /rubric used to do); a Provincial Admin sees
 * a picker for every agency of their own agency_type there.
 */
export default function GovernanceIndexPage() {
  const router = useRouter();
  useEffect(() => { router.replace('/governance/severity'); }, [router]);
  return null;
}
