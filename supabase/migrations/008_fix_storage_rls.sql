-- Migration 008: Fix Storage RLS Policies for Bluebook and Vehicle Photos

-- Storage RLS Policies for bluebook-documents (Private)
DROP POLICY IF EXISTS "Private Bluebook Select Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Insert Policy" ON storage.objects;
DROP POLICY IF EXISTS "Private Bluebook Delete Policy" ON storage.objects;

CREATE POLICY "Private Bluebook Select Policy"
    ON storage.objects FOR SELECT
    TO anon, authenticated
    USING (
        bucket_id = 'bluebook-documents'
    );

CREATE POLICY "Private Bluebook Insert Policy"
    ON storage.objects FOR INSERT
    TO anon, authenticated
    WITH CHECK (bucket_id = 'bluebook-documents');

CREATE POLICY "Private Bluebook Delete Policy"
    ON storage.objects FOR DELETE
    TO anon, authenticated
    USING (
        bucket_id = 'bluebook-documents'
    );

-- Storage RLS Policies for auction-images (Public)
DROP POLICY IF EXISTS "Public Auction Images Access" ON storage.objects;
CREATE POLICY "Public Auction Images Access"
    ON storage.objects FOR ALL
    TO anon, authenticated, public
    USING (bucket_id = 'auction-images')
    WITH CHECK (bucket_id = 'auction-images');
