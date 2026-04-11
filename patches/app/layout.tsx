import type { Metadata } from 'next';
import { getMessages } from 'next-intl/server';
import { NextIntlClientProvider } from 'next-intl';
import '@/styles/globals.css';
import { QueryProvider } from '@/components/providers/query-provider';
import { ThemeProvider } from '@/components/theme/theme-provider';

export const metadata: Metadata = {
  title: 'Pan by Euraika',
  description: 'Pan — AI workspace for chat, skills, integrations, runtime trust, and workspace inspection. By Euraika.',
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const messages = await getMessages();

  return (
    <html lang="zh-CN" suppressHydrationWarning>
      <body className="min-h-screen bg-background text-foreground">
        <NextIntlClientProvider messages={messages}>
          <ThemeProvider>
            <QueryProvider>{children}</QueryProvider>
          </ThemeProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
