SRC_DIR       ?= ..
ARTIFACTS     ?= artifacts
BUILD_CONTEXT ?= ..

BASE_IMAGE    ?= astra-linux:2.12-glibc2.28
IMAGE         ?= samba-ad:latest

.DEFAULT_GOAL := help
.PHONY: help build sources

GCC_VERSION    ?= 8.5.0
PYTHON_VERSION ?= 3.11.12
GMP_VERSION    ?= 6.1.2
MPFR_VERSION   ?= 4.0.2
MPC_VERSION    ?= 1.1.0
SAMBA_VERSION  ?= 4.21.3
GNUTLS_VERSION ?= 3.8.4
GNUTLS_SERIES  ?= 3.8
NETTLE_VERSION ?= 3.9.1
KRB5_VERSION   ?= 1.21.3
KRB5_SERIES    ?= 1.21


help:
	@echo "  make sources    скачать исходники gcc/gmp/mpfr/mpc/python/samba (нужен инет)"
	@echo "  make build      собрать $(IMAGE) (база: $(BASE_IMAGE))"


# Скачать исходники сборки (gcc/gmp/mpfr/mpc/python + nettle/gnutls/krb5/samba)
sources:
	@mkdir -p $(ARTIFACTS)/gcc-src $(ARTIFACTS)/python-src $(ARTIFACTS)/samba-src
	@set -e; for spec in \
	  "$(ARTIFACTS)/gcc-src/gcc-$(GCC_VERSION).tar.xz=https://ftp.gnu.org/gnu/gcc/gcc-$(GCC_VERSION)/gcc-$(GCC_VERSION).tar.xz" \
	  "$(ARTIFACTS)/gcc-src/gmp-$(GMP_VERSION).tar.xz=https://ftp.gnu.org/gnu/gmp/gmp-$(GMP_VERSION).tar.xz" \
	  "$(ARTIFACTS)/gcc-src/mpfr-$(MPFR_VERSION).tar.xz=https://ftp.gnu.org/gnu/mpfr/mpfr-$(MPFR_VERSION).tar.xz" \
	  "$(ARTIFACTS)/gcc-src/mpc-$(MPC_VERSION).tar.gz=https://ftp.gnu.org/gnu/mpc/mpc-$(MPC_VERSION).tar.gz" \
	  "$(ARTIFACTS)/python-src/Python-$(PYTHON_VERSION).tar.xz=https://www.python.org/ftp/python/$(PYTHON_VERSION)/Python-$(PYTHON_VERSION).tar.xz" \
	  "$(ARTIFACTS)/samba-src/nettle-$(NETTLE_VERSION).tar.gz=https://ftp.gnu.org/gnu/nettle/nettle-$(NETTLE_VERSION).tar.gz" \
	  "$(ARTIFACTS)/samba-src/gnutls-$(GNUTLS_VERSION).tar.xz=https://www.gnupg.org/ftp/gcrypt/gnutls/v$(GNUTLS_SERIES)/gnutls-$(GNUTLS_VERSION).tar.xz" \
	  "$(ARTIFACTS)/samba-src/krb5-$(KRB5_VERSION).tar.gz=https://kerberos.org/dist/krb5/$(KRB5_SERIES)/krb5-$(KRB5_VERSION).tar.gz" \
	  "$(ARTIFACTS)/samba-src/samba-$(SAMBA_VERSION).tar.gz=https://download.samba.org/pub/samba/stable/samba-$(SAMBA_VERSION).tar.gz" \
	; do \
	  dest="$${spec%%=*}"; url="$${spec#*=}"; \
	  if [ -f "$$dest" ]; then echo "  ✓ $$dest"; \
	  else echo ">>> $$url"; curl -fSL -o "$$dest" "$$url"; fi; \
	done


build:
	@docker image inspect $(BASE_IMAGE) >/dev/null 2>&1 || { \
	  echo "ERROR: нет базового образа $(BASE_IMAGE) — собери его: (cd ../../astra-linux && make build)"; exit 1; }
	@echo ">>> building: $(IMAGE) (target runtime)"
	docker build -f Dockerfile --target runtime -t $(IMAGE) $(BUILD_CONTEXT) --progress plain
	@docker images $(IMAGE)
