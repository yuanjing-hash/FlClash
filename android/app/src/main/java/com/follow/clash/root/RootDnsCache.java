package com.follow.clash.root;

import android.os.IBinder;
import android.os.Parcel;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

final class RootDnsCache {
    interface Resolver {
        void flush(int networkId) throws Exception;
    }

    interface Command {
        ShellResult run(List<String> arguments) throws Exception;
    }

    private static final String DESCRIPTOR = "android.net.IDnsResolver";
    // Stable IDnsResolver AIDL fixes this method's ID; its Java Stub is absent from modular Android's app_process.
    private static final int FLUSH_NETWORK_CACHE = IBinder.FIRST_CALL_TRANSACTION + 10;

    private final Resolver resolver;
    private final Command command;

    RootDnsCache(IBinder service) {
        this(networkId -> flushNetworkCache(service, networkId));
    }

    RootDnsCache(Resolver resolver) {
        this(resolver, arguments -> new RootShell(65537).execute(arguments, 2_000, new byte[0]));
    }

    RootDnsCache(Resolver resolver, Command command) {
        this.resolver = resolver;
        this.command = command;
    }

    void flush(int[] networkIds) throws Exception {
        List<Exception> failures = new ArrayList<>();
        for (int networkId : networkIds) {
            try {
                resolver.flush(networkId);
            } catch (Exception error) {
                failures.add(error);
            }
        }
        try {
            ShellResult result = command.run(Arrays.asList("/system/bin/cmd", "activity", "broadcast", "--user", "all",
                "-a", "android.intent.action.CLEAR_DNS_CACHE", "--receiver-registered-only"));
            if (!result.getSuccess() || !result.getStderr().trim().isEmpty()
                || !result.getStdout().contains("Broadcast completed:")) {
                throw new IOException("Application DNS cache refresh was not acknowledged");
            }
        } catch (Exception error) {
            failures.add(error);
        }
        if (!failures.isEmpty()) {
            IOException error = new IOException("DNS cache refresh incomplete");
            for (Exception failure : failures) error.addSuppressed(failure);
            throw error;
        }
    }

    private static void flushNetworkCache(IBinder service, int networkId) throws Exception {
        if (service == null || !DESCRIPTOR.equals(service.getInterfaceDescriptor())) {
            throw new IOException("DNS resolver service is unavailable");
        }
        Parcel data = Parcel.obtain();
        Parcel reply = Parcel.obtain();
        try {
            data.writeInterfaceToken(DESCRIPTOR);
            data.writeInt(networkId);
            if (!service.transact(FLUSH_NETWORK_CACHE, data, reply, 0)) {
                throw new IOException("DNS resolver cache refresh is unsupported");
            }
            reply.readException();
        } finally {
            reply.recycle();
            data.recycle();
        }
    }
}
