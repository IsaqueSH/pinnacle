// SPDX-License-Identifier: GPL-3.0-or-later

use std::cell::RefCell;

use smithay::output::Output;

use crate::{state::WithState, tag::Tag};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
pub struct OutputName(pub String);

#[derive(Default)]
pub struct OutputState {
    pub tags: Vec<Tag>,
}

impl WithState for Output {
    type State = OutputState;

    fn with_state<F, T>(&self, mut func: F) -> T
    where
        F: FnMut(&mut Self::State) -> T,
    {
        self.user_data()
            .insert_if_missing(RefCell::<Self::State>::default);

        let state = self
            .user_data()
            .get::<RefCell<Self::State>>()
            .expect("RefCell not in data map");

        func(&mut state.borrow_mut())
    }
}

impl OutputState {
    pub fn focused_tags(&self) -> impl Iterator<Item = &Tag> {
        self.tags.iter().filter(|tag| tag.active())
    }
}
