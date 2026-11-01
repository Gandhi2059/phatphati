-- Migration 009: Grant FOR ALL permissions (SELECT, INSERT, UPDATE, DELETE) on storage.objects for bluebook-documents

DROP POLICY IF EXISTS "Private Bluebook Select Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Insert Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Delete Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Access Policy" ON storage.objects;

CREATE POLICY "Private Bluebook Access Policy"
    ON storage.objects FOR ALL
    TO anon, authenticated, public
    USING (bucket_id = 'bluebook-documents')
    WITH CHECK (bucket_id = 'bluebook-documents');
 