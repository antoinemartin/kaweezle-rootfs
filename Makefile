# On Apline, you will need the following packages:
# apk --update add curl libarchive-tools sudo
BUILDDIR = $(PWD)/build

OUT_ZIP=$(BUILDDIR)/kaweezle.zip
LNCR_EXE=kaweezle.exe

DLR=curl
DLR_FLAGS=-L
BASE_URL=https://dl-cdn.alpinelinux.org/alpine/v3.15/releases/x86_64/alpine-minirootfs-3.15.0-x86_64.tar.gz
LNCR_ZIP_URL=https://github.com/yuk7/wsldl/releases/download/21082800/icons.zip
LNCR_ZIP_EXE=Alpine.exe
KUBERNETES_VERSION=1.23.1

KUBERNETES_CONTAINER_IMAGES=k8s.gcr.io/pause:3.6 \
	k8s.gcr.io/kube-controller-manager:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/etcd:3.5.1-0 \
	k8s.gcr.io/kube-proxy:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/kube-scheduler:v$(KUBERNETES_VERSION) \
	k8s.gcr.io/coredns/coredns:v1.8.6 \
	k8s.gcr.io/kube-apiserver:v$(KUBERNETES_VERSION)


BASE_CONTAINER_IMAGES=docker.io/rancher/local-path-provisioner:v0.0.20 \
	docker.io/rancher/mirrored-flannelcni-flannel-cni-plugin:v1.0.0 \
	quay.io/coreos/flannel:v0.15.1 \
	quay.io/metallb/controller:v0.11.0 \
	quay.io/metallb/speaker:v0.11.0 \
	k8s.gcr.io/metrics-server/metrics-server:v0.5.2

CONTAINER_IMAGES=$(KUBERNETES_CONTAINER_IMAGES) $(BASE_CONTAINER_IMAGES)

.PHONY: make_images default clean kwsl

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

$(BUILDDIR)/rootfs.tar.gz: $(BUILDDIR)/rootfs $(BUILDDIR)/rootfs/kwsl
	@echo -e '\e[1;31mBuilding rootfs.tar.gz...\e[m'
	bsdtar -zcpf $@ -C $< `ls $<`
	chown `id -un` $@

$(BUILDDIR)/rootfs: $(BUILDDIR)/base.tar.gz wslimage/profile
	@echo -e '\e[1;31mBuilding rootfs...\e[m'
	mkdir -p $@
	bsdtar -zxpkf $(BUILDDIR)/base.tar.gz -C $@
	cp -f /etc/resolv.conf $@/etc/resolv.conf
	cp -f wslimage/profile $@/etc/profile
	grep -q edge/testing $@/etc/apk/repositories || echo "http://dl-cdn.alpinelinux.org/alpine/edge/testing/" >> $@/etc/apk/repositories
	chroot $@ /sbin/apk --update-cache add zsh oh-my-zsh cri-o kubelet kubeadm kubectl kubelet-openrc cri-o-contrib-cni util-linux-misc git
	mv $@/etc/cni/net.d/10-crio-bridge.conf $@/etc/cni/net.d/12-crio-bridge.conf || /bin/true
	cp -f $@/usr/share/oh-my-zsh/templates/zshrc.zsh-template $@/root/.zshrc
	chmod +x $@/root/.zshrc
	sed -ie '/^root:/ s#:/bin/.*$$#:/bin/zsh#' $@/etc/passwd
	echo "# This file was automatically generated by WSL. To stop automatic generation of this file, remove this line." | tee $@/etc/resolv.conf
	rm -rf `find $@/var/cache/apk/ -type f`
	mkdir -p $@/var/lib/containers/storage
	sed -ie '/^graphroot = / s#.*$$#graphroot = "$@/var/lib/containers/storage"#' /etc/containers/storage.conf
	sed -ie 's/^#mount_program/mount_program/' /etc/containers/storage.conf
	$(foreach I, $(CONTAINER_IMAGES), skopeo copy docker://$I containers-storage:$I;)
	-umount $@/var/lib/containers/storage/overlay
	chmod +x $@

$(BUILDDIR)/rootfs/kwsl: $(BUILDDIR)/rootfs
	go mod tidy
	go build -o $@ -ldflags "-X k8s.KUBERNETES_VERSION=$(KUBERNETES_VERSION)"

# For this to work, you need to have cri-o and skopeo installed locally
make_images: $(BUILDDIR)/rootfs
	sed -ie '/^graphroot = / s#.*$$#graphroot = "$</var/lib/containers/storage"#' /etc/containers/storage.conf
	sed -ie 's/^#mount_program/mount_program/' /etc/containers/storage.conf
	$(foreach I, $(CONTAINER_IMAGES), skopeo copy docker://$I containers-storage:$I;)
	umount $</var/lib/containers/storage/overlay

$(BUILDDIR)/images: $(BUILDDIR)/images.tar.gz
	@echo -e '\e[1;31mUncompressing images...\e[m'
	bsdtar -zxvf $< -C $(BUILDDIR)

$(BUILDDIR)/base.tar.gz: | $(BUILDDIR)
	@echo -e '\e[1;31mDownloading base.tar.gz...\e[m'
	$(DLR) $(DLR_FLAGS) $(BASE_URL) -o $@

$(BUILDDIR)/icons.zip: | $(BUILDDIR)
	@echo -e '\e[1;31mDownloading icons.zip...\e[m'
	$(DLR) $(DLR_FLAGS) $(LNCR_ZIP_URL) -o $@

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

clean:
	@echo -e '\e[1;31mCleaning files...\e[m'
	-rm -rf $(BUILDDIR)
	rm -f kwsl

print-%  : ; @echo $* = $($*)
