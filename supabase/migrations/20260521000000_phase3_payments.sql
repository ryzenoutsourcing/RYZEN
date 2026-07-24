-- Phase 3: Commercial Completion - Payment Infrastructure (SECURED)

-- 1. Extend bookings table
ALTER TABLE bookings
ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'unpaid',
ADD COLUMN IF NOT EXISTS stripe_session_id TEXT,
ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
ADD COLUMN IF NOT EXISTS invoice_id TEXT,
ADD COLUMN IF NOT EXISTS invoice_pdf_url TEXT,
ADD COLUMN IF NOT EXISTS payment_method_type TEXT;

-- 2. Create payments table
CREATE TABLE IF NOT EXISTS payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id TEXT REFERENCES bookings(id),
    customer_id TEXT, -- reference to customers.id (TEXT)
    stripe_session_id TEXT UNIQUE,
    stripe_payment_intent_id TEXT UNIQUE,
    amount DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'EUR',
    status TEXT NOT NULL, -- pending, succeeded, failed
    payment_method TEXT, -- card, bancontact, etc.
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create refunds table
CREATE TABLE IF NOT EXISTS refunds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id UUID REFERENCES payments(id),
    booking_id TEXT REFERENCES bookings(id),
    stripe_refund_id TEXT UNIQUE,
    amount DECIMAL(10, 2) NOT NULL,
    status TEXT NOT NULL, -- pending, completed, failed
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Create invoices table
CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id TEXT REFERENCES bookings(id),
    stripe_invoice_id TEXT UNIQUE,
    invoice_number TEXT,
    invoice_pdf_url TEXT,
    hosted_invoice_url TEXT,
    status TEXT, -- draft, open, paid, void, uncollectible
    amount_due DECIMAL(10, 2),
    amount_paid DECIMAL(10, 2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Create settlements table (for operator reconciliation)
CREATE TABLE IF NOT EXISTS settlements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    stripe_payout_id TEXT UNIQUE,
    amount DECIMAL(10, 2) NOT NULL,
    currency TEXT DEFAULT 'EUR',
    status TEXT, -- pending, paid, failed, canceled
    arrival_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Create transaction_ledger (double-entry style record)
CREATE TABLE IF NOT EXISTS transaction_ledger (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id TEXT REFERENCES bookings(id),
    entity_type TEXT, -- payment, refund, settlement
    entity_id UUID, -- reference to id in payments, refunds, or settlements
    amount DECIMAL(10, 2) NOT NULL,
    entry_type TEXT, -- credit, debit
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_payments_booking_id ON payments(booking_id);
CREATE INDEX IF NOT EXISTS idx_refunds_booking_id ON refunds(booking_id);
CREATE INDEX IF NOT EXISTS idx_invoices_booking_id ON invoices(booking_id);
CREATE INDEX IF NOT EXISTS idx_ledger_booking_id ON transaction_ledger(booking_id);

-- 8. RLS Policies (STRICT SECURED)
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE settlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE transaction_ledger ENABLE ROW LEVEL SECURITY;

-- DROP EXISTING TO BE SURE
DROP POLICY IF EXISTS "Service role full access payments" ON payments;
DROP POLICY IF EXISTS "Users can view own payments" ON payments;
DROP POLICY IF EXISTS "Service role full access refunds" ON refunds;
DROP POLICY IF EXISTS "Users can view own refunds" ON refunds;
DROP POLICY IF EXISTS "Service role full access invoices" ON invoices;
DROP POLICY IF EXISTS "Users can view own invoices" ON invoices;
DROP POLICY IF EXISTS "Service role full access settlements" ON settlements;
DROP POLICY IF EXISTS "Service role full access ledger" ON transaction_ledger;

-- SECURE POLICIES
-- Service Role
CREATE POLICY "Service role full access payments" ON payments FOR ALL TO service_role USING (true);
CREATE POLICY "Service role full access refunds" ON refunds FOR ALL TO service_role USING (true);
CREATE POLICY "Service role full access invoices" ON invoices FOR ALL TO service_role USING (true);
CREATE POLICY "Service role full access settlements" ON settlements FOR ALL TO service_role USING (true);
CREATE POLICY "Service role full access ledger" ON transaction_ledger FOR ALL TO service_role USING (true);

-- Authenticated Users (Read Only for their own records)
-- Since we use CUST-email as ID, we can join with bookings/customers
-- For simplicity and maximum security, we'll allow access if the customer_id matches.
CREATE POLICY "Users can view own payments" ON payments FOR SELECT TO authenticated
USING (customer_id = (SELECT id FROM customers WHERE email = auth.jwt()->>'email'));

CREATE POLICY "Users can view own refunds" ON refunds FOR SELECT TO authenticated
USING (booking_id IN (SELECT id FROM bookings WHERE customer_id = (SELECT id FROM customers WHERE email = auth.jwt()->>'email')));

CREATE POLICY "Users can view own invoices" ON invoices FOR SELECT TO authenticated
USING (booking_id IN (SELECT id FROM bookings WHERE customer_id = (SELECT id FROM customers WHERE email = auth.jwt()->>'email')));

-- Operator (Admin) access
-- Assuming admins are authenticated and have specific claims or we check a table.
-- For Phase 3, we allow all authenticated users to select from settlements/ledger if they are admins (placeholder logic)
-- CREATE POLICY "Admins can view settlements" ON settlements FOR SELECT TO authenticated USING (auth.jwt()->>'role' = 'admin');
