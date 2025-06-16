package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/runtime/serializer/json"
)

const (
	GroupName         = "resource.pythoner6.dev"
	Version           = "v1alpha1"
	YubikeyConfigKind = "YubikeyConfig"
)

// +k8s:deepcopy-gen=false
type Interface interface {
	Normalize() error
	Validate() error
}

var Decoder runtime.Decoder

func init() {
	scheme := runtime.NewScheme()
	schemeGroupVersion := schema.GroupVersion{
		Group:   GroupName,
		Version: Version,
	}
	scheme.AddKnownTypes(schemeGroupVersion, &YubikeyConfig{})
	metav1.AddToGroupVersion(scheme, schemeGroupVersion)
	Decoder = json.NewSerializerWithOptions(
		json.DefaultMetaFactory,
		scheme,
		scheme,
		json.SerializerOptions{
			Pretty: true,
			Strict: true,
		},
	)
}
