'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

/**
 * The root sends everyone to the sign-in page - except a person arriving from
 * an emailed Supabase link.
 *
 * Supabase sends the tokens for a password reset or an invite in the URL
 * FRAGMENT, to whatever redirect it accepted. When the address it was asked to
 * use is not on the project's Redirect URLs allow-list it quietly falls back to
 * the Site URL - this page - and drops the path. A plain `redirect('/login')`
 * here threw the tokens away, so the emailed link opened a sign-in page and the
 * reset silently went nowhere.
 *
 * A fragment is never sent to a server, so this has to be a client component
 * that reads `window.location.hash` and forwards it, intact, to the page that
 * knows what to do with it.
 */
export default function RootPage() {
  const router = useRouter();

  useEffect(() => {
    const hash = window.location.hash;
    const params = new URLSearchParams(hash.slice(1));
    const type = params.get('type');

    if (type === 'recovery' || params.get('error_code')) {
      // An expired-link error carries no `type`; it reaches the reset page
      // because that is where a person recovering an account would be, and the
      // page turns it into "request a new link".
      router.replace(`/reset-password${hash}`);
    } else if (type === 'invite') {
      router.replace(`/accept-invite${hash}`);
    } else {
      router.replace('/login');
    }
  }, [router]);

  return null;
}
