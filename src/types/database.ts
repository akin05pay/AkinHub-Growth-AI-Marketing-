export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

// Replace this bootstrap type with the output of:
// supabase gen types typescript --project-id <project-ref>
export type Database = Record<string, never>;
