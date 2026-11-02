-- Run after 01_tables.sql and 02_foreign_keys.sql.
-- State changes that leave the status unchanged are allowed.
CREATE FUNCTION check_order_status_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.order_status IS DISTINCT FROM OLD.order_status AND NOT (
        (OLD.order_status = 'PENDING' AND NEW.order_status IN ('CONFIRMED', 'FAILED')) OR
        (OLD.order_status = 'CONFIRMED' AND NEW.order_status IN ('IN_PROGRESS', 'CANCELLED')) OR
        (OLD.order_status = 'IN_PROGRESS' AND NEW.order_status IN ('COMPLETED', 'CANCELLED')) OR
        (OLD.order_status = 'CANCELLED' AND NEW.order_status = 'FAILED')
    ) THEN
        RAISE EXCEPTION 'Invalid order status transition: % -> %', OLD.order_status, NEW.order_status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_order_status_transition BEFORE UPDATE OF order_status ON service_orders
    FOR EACH ROW EXECUTE FUNCTION check_order_status_transition();

CREATE FUNCTION check_preparation_status_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.preparation_status IS DISTINCT FROM OLD.preparation_status AND NOT (
        (OLD.preparation_status = 'PENDING' AND NEW.preparation_status = 'PREPARING') OR
        (OLD.preparation_status = 'PREPARING' AND NEW.preparation_status = 'READY')
    ) THEN
        RAISE EXCEPTION 'Invalid preparation status transition: % -> %', OLD.preparation_status, NEW.preparation_status
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_preparation_status_transition BEFORE UPDATE OF preparation_status ON food_orders
    FOR EACH ROW EXECUTE FUNCTION check_preparation_status_transition();

-- Payment transitions and preservation of the original payment time on refund.
CREATE FUNCTION check_payment_status_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status AND NOT (
        (OLD.payment_status = 'PENDING' AND NEW.payment_status IN ('PAID', 'FAILED')) OR
        (OLD.payment_status = 'FAILED' AND NEW.payment_status = 'PENDING') OR
        (OLD.payment_status = 'PAID' AND NEW.payment_status = 'REFUNDED')
    ) THEN
        RAISE EXCEPTION 'Invalid payment status transition: % -> %', OLD.payment_status, NEW.payment_status
            USING ERRCODE = 'check_violation';
    END IF;
    IF OLD.payment_status IN ('PAID', 'REFUNDED') AND NEW.payment_status = 'REFUNDED'
       AND NEW.paid_at IS DISTINCT FROM OLD.paid_at THEN
        RAISE EXCEPTION 'A refund must retain the original paid_at'
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_payment_status_transition BEFORE UPDATE ON payments
    FOR EACH ROW EXECUTE FUNCTION check_payment_status_transition();

-- Lock the parent before subtype changes so concurrent writers cannot both
-- add different subtypes for the same order. Order IDs are immutable.
CREATE FUNCTION lock_subtype_parent() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_id entity_id;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.order_id IS DISTINCT FROM OLD.order_id THEN
        RAISE EXCEPTION 'Order IDs cannot be changed' USING ERRCODE = 'check_violation';
    END IF;
    target_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    PERFORM 1 FROM service_orders WHERE order_id = target_id FOR UPDATE;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_food_lock BEFORE INSERT OR UPDATE OR DELETE ON food_orders
    FOR EACH ROW EXECUTE FUNCTION lock_subtype_parent();
CREATE TRIGGER trg_delivery_lock BEFORE INSERT OR UPDATE OR DELETE ON delivery_orders
    FOR EACH ROW EXECUTE FUNCTION lock_subtype_parent();
CREATE TRIGGER trg_mobility_lock BEFORE INSERT OR UPDATE OR DELETE ON mobility_orders
    FOR EACH ROW EXECUTE FUNCTION lock_subtype_parent();

CREATE FUNCTION check_order_specialization() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE target_id entity_id; subtype_count INTEGER;
BEGIN
    target_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.order_id ELSE NEW.order_id END;
    -- A deleted parent does not need a subtype.
    IF NOT EXISTS (SELECT 1 FROM service_orders WHERE order_id = target_id) THEN RETURN NULL; END IF;
    SELECT (EXISTS (SELECT 1 FROM food_orders WHERE order_id = target_id))::integer
         + (EXISTS (SELECT 1 FROM delivery_orders WHERE order_id = target_id))::integer
         + (EXISTS (SELECT 1 FROM mobility_orders WHERE order_id = target_id))::integer
      INTO subtype_count;
    IF subtype_count <> 1 THEN
        RAISE EXCEPTION 'Order % must have exactly one subtype (found %)', target_id, subtype_count
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER trg_order_specialization AFTER INSERT OR UPDATE ON service_orders
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_order_specialization();
CREATE CONSTRAINT TRIGGER trg_food_specialization AFTER INSERT OR UPDATE OR DELETE ON food_orders
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_order_specialization();
CREATE CONSTRAINT TRIGGER trg_delivery_specialization AFTER INSERT OR UPDATE OR DELETE ON delivery_orders
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_order_specialization();
CREATE CONSTRAINT TRIGGER trg_mobility_specialization AFTER INSERT OR UPDATE OR DELETE ON mobility_orders
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION check_order_specialization();

-- Identifiers are assigned once by the generator and do not change.
CREATE FUNCTION prevent_identifier_change() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF to_jsonb(NEW)->TG_ARGV[0] IS DISTINCT FROM to_jsonb(OLD)->TG_ARGV[0] THEN
        RAISE EXCEPTION '% cannot be changed', TG_ARGV[0] USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_customer_id_immutable BEFORE UPDATE OF customer_id ON customers
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('customer_id');
CREATE TRIGGER trg_order_id_immutable BEFORE UPDATE OF order_id ON service_orders
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('order_id');
CREATE TRIGGER trg_service_area_id_immutable BEFORE UPDATE OF service_area_id ON service_areas
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('service_area_id');
CREATE TRIGGER trg_location_id_immutable BEFORE UPDATE OF location_id ON locations
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('location_id');
CREATE TRIGGER trg_merchant_outlet_id_immutable BEFORE UPDATE OF merchant_outlet_id ON merchant_outlets
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('merchant_outlet_id');
CREATE TRIGGER trg_payment_id_immutable BEFORE UPDATE OF payment_id ON payments
    FOR EACH ROW EXECUTE FUNCTION prevent_identifier_change('payment_id');
