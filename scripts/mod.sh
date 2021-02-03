#!/bin/bash

cd $OPENWRTROOT

#add obfs-server
sed  -i -e "s/# CONFIG_PACKAGE_simple-obfs-server is not set/CONFIG_PACKAGE_simple-obfs-server=y/g" .config


#fix bonding
sed  -i -e "s/CONFIG_PACKAGE_kmod-bonding=m/CONFIG_PACKAGE_kmod-bonding=y/g" .config


pushd target/linux/bcm27xx/patches-5.4/
cat > 999-fix-bonding.patch <<eof
--- a/drivers/net/bonding/bond_main.c	2020-07-09 15:37:57.000000000 +0800
+++ b/drivers/net/bonding/bond_main.c	2020-08-02 06:06:22.273345612 +0800
@@ -1486,12 +1486,12 @@
 			if (!bond_has_slaves(bond)) {
 				bond->params.fail_over_mac = BOND_FOM_ACTIVE;
 				slave_warn(bond_dev, slave_dev, "Setting fail_over_mac to active for active-backup mode\n");
-			} else {
+			} /* else {
 				NL_SET_ERR_MSG(extack, "Slave device does not support setting the MAC address, but fail_over_mac is not set to active");
 				slave_err(bond_dev, slave_dev, "The slave device specified does not support setting the MAC address, but fail_over_mac is not set to active\n");
 				res = -EOPNOTSUPP;
 				goto err_undo_flags;
-			}
+			} */
 		}
 	}
 
@@ -1544,7 +1544,7 @@
 		ss.ss_family = slave_dev->type;
 		res = dev_set_mac_address(slave_dev, (struct sockaddr *)&ss,
 					  extack);
-		if (res) {
+		if (res && res != -EOPNOTSUPP) {
 			slave_err(bond_dev, slave_dev, "Error %d calling set_mac_address\n", res);
 			goto err_restore_mtu;
 		}

eof
popd

#add setsid

echo "CONFIG_PACKAGE_setsid=y" >> .config

pushd package
mkdir -p setsid/src
popd

pushd package/setsid

cat > Makefile <<eof
include \$(TOPDIR)/rules.mk

PKG_NAME:=setsid
PKG_RELEASE:=0.1

PKG_BUILD_DIR := \$(BUILD_DIR)/\$(PKG_NAME)

include \$(INCLUDE_DIR)/package.mk

define Package/setsid
	SECTION:=utils
	CATEGORY:=Utilities
	TITLE:=setsid -- execute a command in a new session
endef

define Build/Prepare
	mkdir -p \$(PKG_BUILD_DIR)
	\$(CP) ./src/* \$(PKG_BUILD_DIR)/
endef

define Package/setsid/install
	\$(INSTALL_DIR) \$(1)/usr/bin
	\$(INSTALL_BIN) \$(PKG_BUILD_DIR)/setsid \$(1)/usr/bin/
endef

\$(eval \$(call BuildPackage,setsid))

eof

cat > src/Makefile <<eof
setsid: setsid.o
	\$(CC) \$(LDFLAGS) setsid.o -o setsid

setsid.o: setsid.c
	\$(CC) \$(CFLAGS) -c setsid.c

clean:
	rm *.o setsid

eof

cat > src/setsid.c <<eof
/*
 * setsid.c -- execute a command in a new session
 */

#include <getopt.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>


static void __attribute__((__noreturn__)) usage(void)
{
	FILE *out = stdout;

	fputs("Run a program in a new session.\n", out);
	fputs(" -c, --ctty     set the controlling terminal to the current one\n", out);
	fputs(" -f, --fork     always fork\n", out);
	fputs(" -w, --wait     wait program to exit, and use the same return\n", out);

	exit(EXIT_SUCCESS);
}

void close_stdout(void)
{
	fclose(stdout);
	fclose(stderr);
}


int main(int argc, char **argv)
{
	int ch, forcefork = 0;
	int ctty = 0;
	pid_t pid;
	int status = 0;

	static const struct option longopts[] = {
		{"ctty", no_argument, NULL, 'c'},
		{"fork", no_argument, NULL, 'f'},
		{"wait", no_argument, NULL, 'w'},
		{"version", no_argument, NULL, 'V'},
		{"help", no_argument, NULL, 'h'},
		{NULL, 0, NULL, 0}
	};

	atexit(close_stdout);

	while ((ch = getopt_long(argc, argv, "+Vhcfw", longopts, NULL)) != -1)
		switch (ch) {
		case 'c':
			ctty=1;
			break;
		case 'f':
			forcefork = 1;
			break;
		case 'w':
			status = 1;
			break;
		case 'h':
		default:
			usage();
		}

	if (argc - optind < 1) {
		usage();
	}

	if (forcefork || getpgrp() == getpid()) {
		pid = fork();
		switch (pid) {
		case -1:
			err(EXIT_FAILURE, "fork");
		case 0:
			/* child */
			break;
		default:
			/* parent */
			if (!status)
				return EXIT_SUCCESS;
			if (wait(&status) != pid)
				err(EXIT_FAILURE, "wait");
			if (WIFEXITED(status))
				return WEXITSTATUS(status);
			err(status, "child %d did not exit normally", pid);
		}
	}
	if (setsid() < 0)
		/* cannot happen */
		err(EXIT_FAILURE, "setsid failed");

	if (ctty && ioctl(STDIN_FILENO, TIOCSCTTY, 1))
		err(EXIT_FAILURE, "failed to set the controlling terminal");
	execvp(argv[optind], argv + optind);
	err(argv[optind]);
}

eof


popd
