# SPDX-License-Identifier: MIT

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netspeedtest
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/muink/luci-app-netspeedtest.git
PKG_SOURCE_VERSION:=master
PKG_MIRROR_HASH:=skip

LUCI_TITLE:=LuCI Net Speedtest
LUCI_DEPENDS:=+iperf3 +librespeed-go +ca-certificates
LUCI_PKGARCH:=all

define Package/luci-app-netspeedtest/conffiles
/etc/config/netspeedtest
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
