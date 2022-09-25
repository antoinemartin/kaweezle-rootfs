# On Apline, you will need the following packages:
# apk --update add curl libarchive-tools sudo
BUILDDIR = $(PWD)/build

OUT_ZIP=$(BUILDDIR)/kaweezle.zip
LNCR_EXE=kaweezle.exe

DLR=curl
DLR_FLAGS=-L
BASE_URL=https://dl-cdn.alpinelinux.org/alpine/v3.16/releases/x86_64/alpine-minirootfs-3.16.0-x86_64.tar.gz
LNCR_ZIP_URL=https://github.com/yuk7/wsldl/releases/download/21082800/icons.zip
LNCR_ZIP_EXE=Alpine.exe
KUBERNETES_VERSION?=1.25.0
IKNITE_VERSION?=0.1.8
IKNITE_KEY_NAME=kaweezle-devel@kaweezle.com-c9d89864.rsa.pub
IKNITE_REPO_URL:=https://kaweezle.com/repo/
IKNITE_BASE_URL:=https://github.com/kaweezle/iknite/releases/download
IKNITE_PUB_KEY_URL:=$(IKNITE_BASE_URL)/v$(IKNITE_VERSION)/$(IKNITE_KEY_NAME)

KUBERNETES_CONTAINER_IMAGES=k8s.gcr.io/pause:3.8 \
	k8s.gcr.io/kube-controller-manager:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/etcd:3.5.4-0 \
	k8s.gcr.io/kube-proxy:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/kube-scheduler:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/coredns/coredns:v1.9.3 \
	k8s.gcr.io/kube-apiserver:v$(KUBERNETES_VERSION)


BASE_CONTAINER_IMAGES=docker.io/rancher/local-path-provisioner:master-head \
	docker.io/rancher/mirrored-flannelcni-flannel-cni-plugin:v1.1.0 \
	rancher/mirrored-flannelcni-flannel:v0.19.2 \
	quay.io/metallb/controller:v0.13.5 \
	quay.io/metallb/speaker:v0.13.5 \
	k8s.gcr.io/metrics-server/metrics-server:v0.6.1

CONTAINER_IMAGES=$(KUBERNETES_CONTAINER_IMAGES) $(BASE_CONTAINER_IMAGES)

.PHONY: default clean kwsl

default: $(OUT_ZIP).sha256 $(BUILDDIR)/rootfs.tar.gz.sha256

%.sha256: %
	sha256sum $< | cut -d' ' -f 1 > $@

$(OUT_ZIP): $(BUILDDIR)/ziproot
	@echo -e '\e[1;31mBuilding $(OUT_ZIP)\e[m'
	bsdtar -a -cf $(OUT_ZIP) -C $< `ls $<`

$(BUILDDIR)/ziproot: $(BUILDDIR)/Launcher.exe $(BUILDDIR)/rootfs.tar.gz
	@echo -e '\e[1;31mBuilding ziproot...\e[m'
	mkdir -p $@
	cp $(BUILDDIR)/Launcher.exe $@/${LNCR_EXE}
	cp $(BUILDDIR)/rootfs.tar.gz $@

$(BUILDDIR)/Launcher.exe: $(BUILDDIR)/icons.zip
	@echo -e '\e[1;31mExtracting Launcher.exe...\e[m'
	bsdtar -xvf $< $(LNCR_ZIP_EXE)
	mv $(LNCR_ZIP_EXE) $@
	touch $@

$(BUILDDIR)/rootfs.tar.gz: $(BUILDDIR)/rootfs
	@echo -e '\e[1;31mBuilding rootfs.tar.gz...\e[m'
	bsdtar -zcpf $@ -C $< `ls $<`
	chown `id -un` $@

$(BUILDDIR)/rootfs: $(BUILDDIR)/base.tar.gz wslimage/rc.conf $(BUILDDIR)/$(IKNITE_KEY_NAME) $(BUILDDIR)/container_images.tar
	@echo -e '\e[1;31mBuilding rootfs...\e[m'
	mkdir -p $@
	bsdtar -zxpkf $(BUILDDIR)/base.tar.gz -C $@
	cp -f /etc/resolv.conf $@/etc/resolv.conf
	cp -f $(BUILDDIR)/$(IKNITE_KEY_NAME) $@/etc/apk/keys/$(IKNITE_KEY_NAME)
	grep -q edge/testing $@/etc/apk/repositories || echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> $@/etc/apk/repositories
	grep -q kaweezle $@/etc/apk/repositories || echo "$(IKNITE_REPO_URL)" >> $@/etc/apk/repositories
	chroot $@ /sbin/apk --update-cache add openrc zsh oh-my-zsh iknite krmfnsops
	mv $@/etc/cni/net.d/10-crio-bridge.conf $@/etc/cni/net.d/12-crio-bridge.conf || /bin/true
	cp -f $@/usr/share/oh-my-zsh/templates/zshrc.zsh-template $@/root/.zshrc
	sed -ie '/^root:/ s#:/bin/.*$$#:/bin/zsh#' $@/etc/passwd
	echo "# This file was automatically generated by WSL. To stop automatic generation of this file, remove this line." | tee $@/etc/resolv.conf
	rm -rf `find $@/var/cache/apk/ -type f`
	mkdir -p $@/var/lib/containers/storage
	sed -ie '/^graphroot = / s#.*$$#graphroot = "$@/var/lib/containers/storage"#' /etc/containers/storage.conf
	podman load -i $(BUILDDIR)/container_images.tar
	rm $@/var/lib/containers/storage/libpod/bolt_state.db
	sed -ie '/^graphroot = / s#.*$$#graphroot = "/var/lib/containers/storage"#' /etc/containers/storage.conf
	chmod +x $@
	mkdir -p $@/lib/rc/init.d
	chroot $@ ln -s /lib/rc/init.d /run/openrc || /bin/true
	touch $@/lib/rc/init.d/softlevel
	[ -f $@/etc/rc.conf.orig ] || mv $@/etc/rc.conf $@/etc/rc.conf.orig
	cp -f wslimage/rc.conf $@/etc/rc.conf

$(BUILDDIR)/container_images.tar:
	podman image pull $(CONTAINER_IMAGES)
	podman image save -m -o $@ $(CONTAINER_IMAGES)

$(BUILDDIR)/images: $(BUILDDIR)/images.tar.gz
	@echo -e '\e[1;31mUncompressing images...\e[m'
	bsdtar -zxvf $< -C $(BUILDDIR)

$(BUILDDIR)/base.tar.gz: | $(BUILDDIR)
	@echo -e '\e[1;31mDownloading base.tar.gz...\e[m'
	$(DLR) $(DLR_FLAGS) $(BASE_URL) -o $@

$(BUILDDIR)/icons.zip: | $(BUILDDIR)
	@echo -e '\e[1;31mDownloading icons.zip...\e[m'
	$(DLR) $(DLR_FLAGS) $(LNCR_ZIP_URL) -o $@

$(BUILDDIR)/$(IKNITE_KEY_NAME): | $(BUILDDIR)
	@echo -e '\e[1;31mDownloading iknite APK public key...\e[m'
	$(DLR) $(DLR_FLAGS) $(IKNITE_PUB_KEY_URL) -o $@

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	@echo -e '\e[1;31mCleaning files...\e[m'
	-rm -rf $(BUILDDIR)
	rm -f kwsl

print-%  : ; @echo $* = $($*)
