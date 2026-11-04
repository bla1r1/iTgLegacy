#import "TGCallDtls.h"

#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/x509.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>
#include <openssl/ec.h>
#include <openssl/srtp.h>
#include <openssl/bio.h>
#include <openssl/pem.h>

static const char *kSrtpProfiles = "SRTP_AES128_CM_SHA1_80";

// The peer checks our fingerprint against what we announced; its chain and
// validity dates are not part of the WebRTC trust model.
static int TGAcceptCertificate(int preverifyOk, X509_STORE_CTX *store) {
	(void)preverifyOk;
	(void)store;
	return 1;
}

@interface TGCallDtls ()
@property (nonatomic, assign) BOOL client;
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, strong) NSString *fingerprint;
@property (nonatomic, assign) SSL_CTX *context;
@property (nonatomic, assign) SSL *ssl;
@property (nonatomic, assign) BIO *readBio;
@property (nonatomic, assign) BIO *writeBio;
@end

@implementation TGCallDtls

- (instancetype)initWithClient:(BOOL)client {
	if ((self = [super init])){
		_client = client;
	}
	return self;
}

- (BOOL)setupWithError:(NSString **)error {
	if (self.ssl)
		return YES;

	SSL_CTX *context = SSL_CTX_new(DTLS_method());
	if (!context){
		if (error) *error = @"SSL_CTX_new failed";
		return NO;
	}
	SSL_CTX_set_min_proto_version(context, DTLS1_2_VERSION);
	SSL_CTX_set_max_proto_version(context, DTLS1_2_VERSION);
	SSL_CTX_set_verify(context, SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT,
	                   TGAcceptCertificate);
	SSL_CTX_set_cipher_list(context,
	        "DEFAULT:!NULL:!aNULL:!SHA256:!SHA384:!aECDH:!AESGCM+AES256:!aPSK:!3DES");
	if (SSL_CTX_set_tlsext_use_srtp(context, kSrtpProfiles) != 0){
		if (error) *error = @"SRTP profile rejected";
		SSL_CTX_free(context);
		return NO;
	}

	EVP_PKEY_CTX *keyContext = EVP_PKEY_CTX_new_id(EVP_PKEY_EC, NULL);
	EVP_PKEY *key = NULL;
	if (!keyContext ||
	    EVP_PKEY_keygen_init(keyContext) <= 0 ||
	    EVP_PKEY_CTX_set_ec_paramgen_curve_nid(keyContext, NID_X9_62_prime256v1) <= 0 ||
	    EVP_PKEY_keygen(keyContext, &key) <= 0){
		if (error) *error = @"ECDSA key generation failed";
		EVP_PKEY_CTX_free(keyContext);
		SSL_CTX_free(context);
		return NO;
	}
	EVP_PKEY_CTX_free(keyContext);

	X509 *certificate = X509_new();
	if (!certificate){
		if (error) *error = @"X509_new failed";
		EVP_PKEY_free(key);
		SSL_CTX_free(context);
		return NO;
	}
	ASN1_INTEGER_set(X509_get_serialNumber(certificate), 1);
	X509_gmtime_adj(X509_get_notBefore(certificate), 0);
	X509_gmtime_adj(X509_get_notAfter(certificate), 60 * 60 * 24 * 365);
	X509_set_version(certificate, 2);
	X509_NAME *name = X509_get_subject_name(certificate);
	X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC,
	                           (const unsigned char *)"WebRTC", -1, -1, 0);
	X509_set_issuer_name(certificate, name);
	X509_set_pubkey(certificate, key);
	if (!X509_sign(certificate, key, EVP_sha256())){
		if (error) *error = @"X509_sign failed";
		X509_free(certificate);
		EVP_PKEY_free(key);
		SSL_CTX_free(context);
		return NO;
	}

	if (SSL_CTX_use_certificate(context, certificate) != 1 ||
	    SSL_CTX_use_PrivateKey(context, key) != 1){
		if (error) *error = @"certificate install failed";
		X509_free(certificate);
		EVP_PKEY_free(key);
		SSL_CTX_free(context);
		return NO;
	}
	EVP_PKEY_free(key);

	unsigned char digest[EVP_MAX_MD_SIZE];
	unsigned int digestLength = 0;
	if (X509_digest(certificate, EVP_sha256(), digest, &digestLength) != 1){
		if (error) *error = @"certificate digest failed";
		X509_free(certificate);
		SSL_CTX_free(context);
		return NO;
	}
	NSMutableString *hex = [NSMutableString string];
	for (unsigned int i = 0; i < digestLength; i++){
		if (i) [hex appendString:@":"];
		[hex appendFormat:@"%02X", digest[i]];
	}
	self.fingerprint = hex;
	X509_free(certificate);

	SSL *ssl = SSL_new(context);
	if (!ssl){
		if (error) *error = @"SSL_new failed";
		SSL_CTX_free(context);
		return NO;
	}
	BIO *readBio = BIO_new(BIO_s_mem());
	BIO *writeBio = BIO_new(BIO_s_mem());
	BIO_set_mem_eof_return(readBio, -1);
	BIO_set_mem_eof_return(writeBio, -1);
	SSL_set_bio(ssl, readBio, writeBio);
	SSL_set_mtu(ssl, 1200);
	if (_client)
		SSL_set_connect_state(ssl);
	else
		SSL_set_accept_state(ssl);

	self.context = context;
	self.ssl = ssl;
	self.readBio = readBio;
	self.writeBio = writeBio;
	return YES;
}

- (void)drain {
	while (BIO_ctrl_pending(self.writeBio) > 0){
		uint8_t record[1400];
		int got = BIO_read(self.writeBio, record, sizeof(record));
		if (got <= 0)
			break;
		if (self.sendRecord)
			self.sendRecord(record, (size_t)got);
	}
}

- (void)readApplicationData {
	// SCTP INIT from the peer arrives here. This client has no data channel,
	// so reading and dropping it is the whole job; leaving it unread fills
	// OpenSSL's buffers and breaks the record layer.
	uint8_t scratch[1200];
	for (;;){
		int got = SSL_read(self.ssl, scratch, sizeof(scratch));
		if (got > 0)
			continue;
		int error = SSL_get_error(self.ssl, got);
		if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE)
			return;
		return;
	}
}

- (void)pump {
	if (!self.ssl)
		return;

	int result = SSL_do_handshake(self.ssl);
	[self drain];

	if (result == 1){
		if (!self.connected){
			self.connected = YES;
			if (self.onConnected)
				self.onConnected();
		}
		[self readApplicationData];
		[self drain];
		return;
	}

	int error = SSL_get_error(self.ssl, result);
	if (error != SSL_ERROR_WANT_READ && error != SSL_ERROR_WANT_WRITE){
		if (self.onFailure)
			self.onFailure([NSString stringWithFormat:@"DTLS handshake error %d", error]);
	}
}

- (void)feed:(const uint8_t *)bytes length:(size_t)length {
	if (!self.ssl || !bytes || !length)
		return;
	BIO_write(self.readBio, bytes, (int)length);
	[self pump];
}

- (void)beginHandshake {
	[self pump];
}

- (void)handleTimeout {
	if (!self.ssl || self.connected)
		return;
	DTLSv1_handle_timeout(self.ssl);
	[self drain];
}

- (BOOL)exportKeyingMaterial:(uint8_t *)out length:(size_t)length {
	if (!self.ssl || !self.connected)
		return NO;
	static const char label[] = "EXTRACTOR-dtls_srtp";
	return SSL_export_keying_material(self.ssl, out, length,
	                                  label, sizeof(label) - 1,
	                                  NULL, 0, 0) == 1;
}

- (void)stop {
	if (self.ssl){
		SSL_free(self.ssl);
		self.ssl = NULL;
		self.readBio = NULL;
		self.writeBio = NULL;
	}
	if (self.context){
		SSL_CTX_free(self.context);
		self.context = NULL;
	}
	self.connected = NO;
	self.sendRecord = nil;
	self.onConnected = nil;
	self.onFailure = nil;
}

- (void)dealloc {
	[self stop];
}

@end
