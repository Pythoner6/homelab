package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

type YubikeyConfig struct {
	metav1.TypeMeta `json:",inline"`
}

func DefaultYubikeyConfig() *YubikeyConfig {
	return &YubikeyConfig{
		TypeMeta: metav1.TypeMeta{
			APIVersion: GroupName + "/" + Version,
			Kind:       YubikeyConfigKind,
		},
	}
}

func (*YubikeyConfig) Normalize() error {
	return nil
}

func (*YubikeyConfig) Validate() error {
	return nil
}
