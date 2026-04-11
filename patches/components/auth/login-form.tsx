'use client';

import { Eye, EyeOff, ShieldCheck } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useTranslations } from 'next-intl';
import { useState } from 'react';

export function LoginForm() {
  const router = useRouter();
  const t = useTranslations('login');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);

    if (!username.trim() || !password) {
      setError(t('errorBothFields'));
      return;
    }

    setIsSubmitting(true);

    const formData = new FormData();
    formData.set('username', username.trim());
    formData.set('password', password);

    const response = await fetch('/api/auth/login', {
      method: 'POST',
      body: formData,
    });

    if (!response.ok) {
      const body = await response.json().catch(() => null);
      setError(body?.error ?? t('errorUnable'));
      setIsSubmitting(false);
      return;
    }

    router.push('/chat');
    router.refresh();
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-5">
      <div className="rounded-2xl border border-border/70 bg-card/60 p-4 text-sm text-muted-foreground">
        <div className="flex items-start gap-3">
          <div className="mt-0.5 flex h-8 w-8 items-center justify-center rounded-xl bg-primary/10 text-primary">
            <ShieldCheck className="h-4 w-4" />
          </div>
          <div>
            <p className="font-medium text-foreground">{t('secureAccess')}</p>
            <p className="mt-1 text-xs leading-5">{t('secureAccessDescription')}</p>
          </div>
        </div>
      </div>

      <label htmlFor="username" className="block space-y-1.5 text-sm">
        <span>{t('username')}</span>
        <input
          id="username"
          name="username"
          value={username}
          onChange={(event) => setUsername(event.target.value)}
          placeholder={t('enterUsername')}
          autoComplete="username"
          className="w-full rounded-md border border-input bg-background px-3 py-2.5 outline-none ring-0 transition focus:border-primary"
        />
      </label>

      <label htmlFor="password" className="block space-y-1.5 text-sm">
        <span>{t('password')}</span>
        <div className="relative">
          <input
            id="password"
            name="password"
            type={showPassword ? 'text' : 'password'}
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            placeholder={t('enterPassword')}
            autoComplete="current-password"
            className="w-full rounded-md border border-input bg-background px-3 py-2.5 pr-11 outline-none ring-0 transition focus:border-primary"
          />
          <button
            type="button"
            onClick={() => setShowPassword((current) => !current)}
            aria-label={showPassword ? t('hidePassword') : t('showPassword')}
            className="absolute right-2 top-1/2 -translate-y-1/2 rounded-md p-1 text-muted-foreground transition hover:text-foreground"
          >
            {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
          </button>
        </div>
      </label>

      {error ? <p className="text-sm text-danger">{error}</p> : null}

      <button
        type="submit"
        disabled={isSubmitting}
        className="w-full rounded-md bg-primary px-4 py-2.5 font-medium text-primary-foreground transition hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isSubmitting ? t('signingIn') : t('signIn')}
      </button>
    </form>
  );
}
