package com.follow.clash.root;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Objects;
import java.util.TreeSet;

final class RootProxyState {
    static Value value(String host, int port, List<String> exclusions, String pac) {
        if ((pac == null || pac.isEmpty()) && (host == null || host.trim().isEmpty() || port <= 0)) return null;
        return new Value(host, port, exclusions, pac);
    }

    static final class Value {
        final String host;
        final int port;
        final List<String> exclusions;
        final String pac;

        Value(String host, int port, List<String> exclusions, String pac) {
            this.pac = pac == null ? "" : pac;
            this.host = this.pac.isEmpty() && host != null ? host.trim().toLowerCase(Locale.ROOT) : "";
            this.port = this.pac.isEmpty() ? port : 0;
            TreeSet<String> normalized = new TreeSet<>();
            if (this.pac.isEmpty()) for (String item : exclusions) {
                if (item != null && !item.trim().isEmpty()) normalized.add(item.trim().toLowerCase(Locale.ROOT));
            }
            this.exclusions = Collections.unmodifiableList(new ArrayList<>(normalized));
        }

        @Override public boolean equals(Object other) {
            if (!(other instanceof Value)) return false;
            Value value = (Value) other;
            return host.equals(value.host) && port == value.port && exclusions.equals(value.exclusions) && pac.equals(value.pac);
        }

        @Override public int hashCode() { return Objects.hash(host, port, exclusions, pac); }
    }

    static final class Lease {
        final Value previous;
        final Value applied;

        Lease(Value previous, Value applied) {
            this.previous = previous;
            this.applied = applied;
        }
    }

    static final class Plan {
        final Value applied;
        final Value target;
        final boolean owned;

        Plan(Value applied, Value target, boolean owned) {
            this.applied = applied;
            this.target = target;
            this.owned = owned;
        }
    }

    interface Backend {
        Value cached() throws Exception;
        Value stored() throws Exception;
        void request(Value target) throws Exception;
        void repairStored(Value target) throws Exception;
    }

    static Plan plan(Value cached, Value stored, Lease lease, Value legacy) {
        Value applied = lease == null ? legacy : lease.applied;
        boolean owned = applied != null && (applied.equals(cached) || applied.equals(stored));
        Value target = lease == null ? null : lease.previous;
        if (Objects.equals(target, applied)) target = null;
        if (owned && cached != null && !cached.equals(applied)) target = cached;
        else if (owned && stored != null && !stored.equals(applied)) target = stored;
        return new Plan(applied, target, owned);
    }

    static void restore(Backend backend, Plan original) throws Exception {
        if (!original.owned) return;
        Value cached = backend.cached();
        Value stored = backend.stored();
        Plan plan = plan(cached, stored, new Lease(original.target, original.applied), null);
        if (!plan.owned) return;
        if (!Objects.equals(cached, plan.target) || !Objects.equals(stored, plan.target)) {
            try {
                backend.request(plan.target);
            } catch (Exception error) {
                if (!Objects.equals(backend.cached(), plan.target)) throw error;
            }
        }
        if (!Objects.equals(backend.cached(), plan.target)) throw new IllegalStateException("System proxy service did not restore its state");
        stored = backend.stored();
        if (!Objects.equals(stored, plan.target)) {
            if (!Objects.equals(stored, plan.applied)) throw new IllegalStateException("System proxy settings changed ownership during restore");
            backend.repairStored(plan.target);
        }
        if (!Objects.equals(backend.cached(), plan.target) || !Objects.equals(backend.stored(), plan.target)) {
            throw new IllegalStateException("System proxy restoration did not persist");
        }
    }
}
